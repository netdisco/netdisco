// The netmap: force-graph on canvas, fed by the same payload and posting the
// same positions as the d3 renderer it replaced.

let graph; // accessor object; the harness and netdisco.js use window.graph
let saveMapPositions; // netdisco.js binds the sidebar Save button to this

/**
 * @typedef {object} NdNetmapWindowProps
 * @property {object} [graph]
 * @property {{move: (function(PointerEvent): void), up: (function(PointerEvent): void)}} [__ndNetmapPointerHandlers]
 */
/** @type {Window & NdNetmapWindowProps} */
const ndWindow = window;

document.addEventListener(
  'htmx:after:swap',
  /**
   * Rebuilds the netmap when htmx swaps in the netmap pane fragment; ignores every other swap.
   * @param {CustomEvent} evt the htmx:after:swap event
   */
  function (evt) {
    // htmx dispatches this on the element that made the request, so the pane
    // is read from the context
    const pane = evt.detail.ctx.target;
    if (pane.id !== 'netmap_pane') return;
    ndNetmap(pane);
  }
);

/**
 * Builds (or rebuilds) the network map inside pane: fetches its JSON payload, tears
 * down any still-running previous ForceGraph instance, and wires up rendering,
 * dragging, box-select, autosave and fullscreen for the new one.
 * @param {HTMLElement} pane the netmap fragment's root element, carrying #nd2_netmap-wrap and its data-nd-* attributes
 * @returns {void}
 */
function ndNetmap(pane) {
  const map = pane.querySelector('#nd2_netmap-wrap');
  if (!(map instanceof HTMLElement)) return;

  $.getJSON(map.dataset.ndDataUrl, function (mapdata) {
    // the netmap fragment reloads in place (do_search's $(target).html()), so
    // this callback runs again while the previous ForceGraph instance's rAF
    // loop is still running; without tearing it down first, its stale
    // onEngineStop fires against the new, still-settling graph through the
    // reassigned global saveMapPositions and can autosave half-settled positions
    if (graph && graph.fg && typeof graph.fg._destructor === 'function') {
      graph.fg._destructor();
    }

    // from here the bottom-right spinner carries the signal through layout to
    // settle, so the two never show at once
    const loading = document.getElementById('nd2_netmap-loading');
    if (loading) {
      loading.remove();
    }

    const container = document.getElementById('nd2_netmap-container');
    if (!(container instanceof HTMLElement)) return;
    const nodes = mapdata['data']['nodes'];

    // radius = 4 + rank of the node's SIZEVALUE among the distinct values
    // (max 4 + numsizes - 1); this approximates the old renderer's sqrt scale
    // over the SIZEVALUE extent, it does not reproduce it exactly
    const distinct = {};
    nodes.forEach(function (n) {
      distinct[n.SIZEVALUE] = true;
    });
    const rankOf = {};
    Object.keys(distinct)
      .map(Number)
      .sort(function (a, b) {
        return a - b;
      })
      .forEach(function (v, i) {
        rankOf[v] = i;
      });

    // the ten categorical colors the old renderer's color10 scheme used,
    // assigned per distinct COLORVALUE in first-appearance order
    const COLOR10 = [
      '#1f77b4',
      '#ff7f0e',
      '#2ca02c',
      '#d62728',
      '#9467bd',
      '#8c564b',
      '#e377c2',
      '#7f7f7f',
      '#bcbd22',
      '#17becf'
    ];
    const colorOf = {};
    let nextColor = 0;

    nodes.forEach(function (n) {
      const key = 'COLORVALUE' in n ? String(n.COLORVALUE) : '__plain';
      if (!(key in colorOf)) {
        colorOf[key] = COLOR10[nextColor++ % 10];
      }
      n.color = colorOf[key];
      n.radius = 4 + (rankOf[n.SIZEVALUE] || 0);
      if (n.fixed) {
        n.fx = +n.x;
        n.fy = +n.y;
        n.x = +n.x;
        n.y = +n.y;
      }
    });

    // centroid of the payload's stored fixed positions, so unpinned nodes
    // gather around a restored layout instead of splitting off toward the
    // origin, and so the camera below can be pointed at that layout
    const fixedNodes = nodes.filter(function (n) {
      return n.fixed;
    });
    let cx = 0,
      cy = 0;
    if (fixedNodes.length) {
      fixedNodes.forEach(function (n) {
        cx += +n.x;
        cy += +n.y;
      });
      cx /= fixedNodes.length;
      cy /= fixedNodes.length;
    }

    // the backend builds links before filtering nodes by group selection, so a
    // link can reference an ID that was filtered out of the node set; force-graph
    // throws mid-simulation on such a dangling reference (the old renderer
    // filtered these out client-side too, d3-force-network-chart.js's "sort out
    // links with invalid node references"), which aborts the paint loop for that
    // tick and leaves nodes drawn only until the next successful repaint (zoom)
    const nodeIds = {};
    nodes.forEach(function (n) {
      nodeIds[n.ID] = true;
    });
    const links = mapdata['data']['links']
      .filter(function (l) {
        return l.FROMID in nodeIds && l.TOID in nodeIds;
      })
      .map(function (l) {
        return { source: l.FROMID, target: l.TOID, SPEED: l.SPEED, INFOSTRING: l.INFOSTRING };
      });

    /**
     * Reads one endpoint's node ID off a link, whether force-graph has resolved it to
     * the node object yet or it is still the plain ID force-graph was given, so any
     * code touching links after resolution can use one helper for both shapes.
     * @param {object} l the link object, source or target either a plain ID or a resolved node object
     * @param {string} end which endpoint to read, "source" or "target"
     * @returns {string} the endpoint's node ID
     */
    function endpointId(l, end) {
      const v = l[end];
      return typeof v === 'object' ? v.ID : v;
    }

    /**
     * Reads whether the autosave checkbox is currently checked. Read fresh at each
     * call rather than cached, because the sidebar toggle can change this checkbox
     * without re-rendering the map.
     * @returns {boolean} true when the autosave checkbox exists and is checked
     */
    function autosaveOn() {
      const box = document.getElementById('nd_autosave');
      return !!(box && box instanceof HTMLInputElement && box.checked);
    }

    // force-graph reheats the simulation on every drag event, and once the first
    // layout has finished alpha is already below d3AlphaMin, so the engine stops
    // again at once having run no ticks. Counting ticks is what tells a real
    // settle apart from those, and without it the save below fires once per
    // mousemove, posting the whole map each time.
    let ticksSinceStop = 0;

    // dragging one selected node carries the rest of the selection; declared
    // here, ahead of the fg chain below, because onNodeDragEnd's closure
    // clears it and is defined as part of that chain
    let dragSnap = null;

    /**
     * Sets the netmap spinner's class to state, guarding against a stale render's tick
     * and engine-stop handlers still firing after the pane holding the spinner has been
     * replaced: nothing destroys this instance until the next fragment's callback
     * reaches the teardown above, so this element may no longer be in the document.
     * @param {string} state the spinner element's new className
     * @returns {void}
     */
    function setSpinnerState(state) {
      const el = document.getElementById('nd2_netmap-spinner');
      if (el && el.className !== state) {
        el.className = state;
      }
    }

    const fg = ForceGraph()(container)
      .width(parseInt(jQuery('#netmap_pane').parent().css('width')))
      .height(window.innerHeight - 100)
      .nodeId('ID')
      .nodeRelSize(1)
      .nodeVal(function (n) {
        return n.radius * n.radius;
      })
      .nodeColor(function (n) {
        return n.color;
      })
      .nodeLabel(function (n) {
        return n.INFOSTRING;
      })
      .linkLabel(function (l) {
        return l.INFOSTRING;
      })
      .linkWidth(1)
      .linkColor(() => 'rgba(150, 150, 150, 0.73)')
      .minZoom(0.1)
      .maxZoom(10)
      .cooldownTime(Infinity)
      .d3AlphaMin(0.001)
      .onNodeDragEnd(function (n) {
        n.fx = n.x;
        n.fy = n.y;
        dragSnap = null;
        // the engine stop that follows a drag runs no ticks, so this is the only
        // place a hand-moved node gets persisted; once per drag, not per mousemove
        if (autosaveOn()) {
          saveMapPositions();
        }
      })
      .onEngineStop(function () {
        setSpinnerState('nd_netmap-settled');
        fg.graphData().nodes.forEach(function (n) {
          n.fx = n.x;
          n.fy = n.y;
        });
        const ranTicks = ticksSinceStop;
        ticksSinceStop = 0;
        if (ranTicks && autosaveOn()) {
          saveMapPositions();
        }
      })
      .graphData({ nodes: nodes, links: links });

    /**
     * Builds a d3-force custom force that pulls every node toward a fixed point along
     * one axis, strength per tick. Used instead of centering on the mean because
     * netdisco maps hold disconnected islands, the same behavior the old renderer's
     * gravity gave.
     * @param {string} axis which coordinate to pull, "x" or "y"
     * @param {number} target the coordinate value nodes are pulled toward
     * @param {number} strength how strongly nodes are pulled toward target each tick
     * @returns {Function} the d3-force force function, ready to pass to fg.d3Force
     */
    function ndPull(axis, target, strength) {
      let ns;
      /**
       * Applies one tick of the pull force to every node captured at initialize.
       * @param {number} alpha the simulation's current alpha (cooling factor)
       * @returns {void}
       */
      function force(alpha) {
        for (let i = 0; i < ns.length; i++) {
          ns[i]['v' + axis] += (target - ns[i][axis]) * strength * alpha;
        }
      }
      force.initialize = function (init) {
        ns = init;
      };
      return force;
    }
    fg.d3Force('charge').strength(-550);
    fg.d3Force('link').distance(120);
    fg.d3Force('center', null);
    // force-graph's origin is the viewport center, unlike the old SVG renderer's
    // top-left origin, so "the middle" above is the stored layout's centroid
    fg.d3Force('pullx', ndPull('x', cx, 0.06));
    fg.d3Force('pully', ndPull('y', cy, 0.06));

    // point the camera at the stored layout; for an all-fresh map cx/cy are
    // (0, 0), force-graph's own default, so this is a no-op there
    fg.centerAt(cx, cy);

    // announce is set only by the sidebar Save button: with autosave on the map
    // saves itself at every settle and every drag, so a toast for each would be
    // noise, but a user who pressed the button has nothing else telling them it
    // worked
    saveMapPositions = function (announce) {
      fg.graphData().nodes.forEach(function (n) {
        n.fx = n.x;
        n.fy = n.y;
      });
      $.post(
        map.dataset.ndSaveUrl,
        $(
          "#nd_vlan-entry, #nd_mapshow-hops, #nd_hgroup-select, #nd_lgroup-select, #nq, input[name='mapshow']"
        ).serialize() +
          '&positions=' +
          JSON.stringify(graph.positions())
      ).done(function () {
        if (announce && !autosaveOn()) {
          ndToast.success('Saved map positions.');
        }
      });
    };

    graph = {
      fg: fg,
      centernode: mapdata['centernode'],
      nodeDataById: function (id) {
        let hit = null;
        fg.graphData().nodes.forEach(function (n) {
          if (n.ID === id) {
            hit = n;
          }
        });
        return hit;
      },
      positions: function () {
        return fg.graphData().nodes.map(function (n) {
          return {
            ID: n.ID,
            x: Math.round(n.x),
            y: Math.round(n.y),
            fixed: n.fx !== undefined && n.fx !== null ? 1 : 0
          };
        });
      },
      links: function () {
        return fg.graphData().links.map(function (l) {
          return { source: endpointId(l, 'source'), target: endpointId(l, 'target') };
        });
      },
      screenXY: function (id) {
        const n = graph.nodeDataById(id);
        if (!n) {
          return null;
        }
        const p = fg.graph2ScreenCoords(n.x, n.y);
        const canvas = container.querySelector('canvas');
        if (!canvas) {
          return null;
        }
        const r = canvas.getBoundingClientRect();
        return { x: r.left + p.x, y: r.top + p.y };
      }
    };
    ndWindow.graph = graph;

    // force-graph exposes no simulation find() and no dblclick callback; its
    // own hit detection delivers the node to onNodeClick, so a double click is
    // two clicks on the same node inside the double-click window
    let lastClick = { id: null, at: 0 };
    fg.onNodeClick(function (n) {
      const now = Date.now();
      // 500 ms matches the platform double-click default the old renderer's
      // dblclick event inherited
      if (n.ID === lastClick.id && now - lastClick.at < 500) {
        window.location.assign(n.LINK);
        return;
      }
      lastClick = { id: n.ID, at: now };
    });

    fg.linkCurvature(function (l) {
      const s = endpointId(l, 'source'),
        t = endpointId(l, 'target');
      return s === t ? 0.6 : 0;
    });

    // the old template zoomed to the center node 1.5 s after start when
    // mapshow=neighbors (a legacy value still reachable from bookmarks)
    if (map.dataset.ndMapshow === 'neighbors') {
      setTimeout(function () {
        const n = graph.nodeDataById(graph.centernode);
        if (n) {
          fg.centerAt(n.x, n.y, 600);
          fg.zoom(4, 600);
        }
      }, 1500);
    }

    // box select: shift-drag replaces the old freehand lasso by ruling.
    // capture-phase listener so force-graph's own pan never sees the drag.
    /** @type {{active: boolean, x0: number, y0: number, el: HTMLElement|null}} */
    const box = { active: false, x0: 0, y0: 0, el: null };
    container.addEventListener(
      'pointerdown',
      function (ev) {
        if (!ev.shiftKey) {
          return;
        }
        ev.stopPropagation();
        ev.preventDefault();
        fg.enablePanInteraction(false).enableZoomInteraction(false);
        box.active = true;
        box.x0 = ev.clientX;
        box.y0 = ev.clientY;
        box.el = document.createElement('div');
        box.el.id = 'nd2_netmap-boxselect';
        // document.body sits outside the fullscreen element, so a box drawn
        // there would be invisible while fullscreen; append into whichever is
        // actually showing
        (document.fullscreenElement || document.body).appendChild(box.el);
      },
      true
    );
    /**
     * Resizes and repositions the box-select rectangle to track the pointer during a
     * shift-drag; does nothing when no box-select is active.
     * @param {PointerEvent} ev the pointermove event
     * @returns {void}
     */
    function onBoxPointerMove(ev) {
      if (!box.active || !box.el) {
        return;
      }
      const x = Math.min(box.x0, ev.clientX),
        y = Math.min(box.y0, ev.clientY);
      box.el.style.left = x + 'px';
      box.el.style.top = y + 'px';
      box.el.style.width = Math.abs(ev.clientX - box.x0) + 'px';
      box.el.style.height = Math.abs(ev.clientY - box.y0) + 'px';
    }
    /**
     * Finishes a box-select drag: removes the selection rectangle, restores pan and
     * zoom, and marks every node inside the box as selected. Does nothing when no
     * box-select is active.
     * @param {PointerEvent} ev the pointerup event
     * @returns {void}
     */
    function onBoxPointerUp(ev) {
      if (!box.active || !box.el || !container) {
        return;
      }
      box.active = false;
      box.el.remove();
      fg.enablePanInteraction(true).enableZoomInteraction(true);
      const canvas = container.querySelector('canvas');
      if (!canvas) {
        return;
      }
      const r = canvas.getBoundingClientRect();
      const a = fg.screen2GraphCoords(Math.min(box.x0, ev.clientX) - r.left, Math.min(box.y0, ev.clientY) - r.top);
      const b = fg.screen2GraphCoords(Math.max(box.x0, ev.clientX) - r.left, Math.max(box.y0, ev.clientY) - r.top);
      fg.graphData().nodes.forEach(function (n) {
        n.selected = n.x >= a.x && n.x <= b.x && n.y >= a.y && n.y <= b.y;
      });
      fg.nodeRelSize(fg.nodeRelSize());
    }
    // raw listeners cannot be namespaced like jQuery's; on a fragment reload,
    // remove the previous render's pair by reference before adding this one,
    // or they accumulate on window forever
    if (ndWindow.__ndNetmapPointerHandlers) {
      window.removeEventListener('pointermove', ndWindow.__ndNetmapPointerHandlers.move);
      window.removeEventListener('pointerup', ndWindow.__ndNetmapPointerHandlers.up);
    }
    ndWindow.__ndNetmapPointerHandlers = { move: onBoxPointerMove, up: onBoxPointerUp };
    window.addEventListener('pointermove', onBoxPointerMove);
    window.addEventListener('pointerup', onBoxPointerUp);

    fg.onNodeDrag(function (n, translate) {
      if (!n.selected) {
        return;
      }
      if (!dragSnap) {
        // hold the node objects themselves, not their IDs: an ID-keyed lookup
        // means a linear nodeDataById() scan per node per tick, and re-keying
        // by ID risks the numeric-vs-string coercion Object.keys() does
        dragSnap = [];
        fg.graphData().nodes.forEach(function (o) {
          if (o.selected && o.ID !== n.ID) {
            dragSnap.push({ node: o, x: o.x, y: o.y });
          }
        });
      }
      // translate is the per-tick incremental delta, not cumulative from drag
      // start, so the snapshot itself has to accumulate it tick by tick
      dragSnap.forEach(function (entry) {
        entry.x += translate.x;
        entry.y += translate.y;
        entry.node.fx = entry.node.x = entry.x;
        entry.node.fy = entry.node.y = entry.y;
      });
    });

    // fullscreen: same API dance the old template used, on the pane so the
    // sidebar stays outside it
    const fullscreenButton = document.getElementById('nd2_netmap-fullscreen');
    if (fullscreenButton) {
      fullscreenButton.addEventListener('click', function () {
        const netmapPane = document.getElementById('netmap_pane');
        if (netmapPane) {
          requestFullScreen(netmapPane);
        }
      });
    }
    // namespaced so a fragment reload's .off() removes only this render's
    // handler instead of every handler ever bound to these shared elements
    $(document)
      .off('.ndnetmap')
      .on('webkitfullscreenchange.ndnetmap mozfullscreenchange.ndnetmap fullscreenchange.ndnetmap', function () {
        resizeGraphContainer();
        $('#nd2_netmap-fullscreen i').attr('class', isFullScreen() ? 'fas fa-compress fa-lg' : 'fas fa-expand fa-lg');
      });

    /**
     * Resizes the graph canvas to the pane's current width after a short delay,
     * letting the sidebar toggle or fullscreen transition finish first.
     * @returns {void}
     */
    function resizeGraphContainer() {
      setTimeout(function () {
        fg.width(parseInt(jQuery('#netmap_pane').parent().css('width'))).height(window.innerHeight - 100);
      }, 500);
    }
    $('#nd_sidebar-toggle-img-in').off('.ndnetmap').on('click.ndnetmap', resizeGraphContainer);
    $('#nd_sidebar-toggle-img-out').off('.ndnetmap').on('click.ndnetmap', resizeGraphContainer);
    $(window).off('resize.ndnetmap').on('resize.ndnetmap', resizeGraphContainer);

    // onEngineTick is a setter, not a subscription, so the tick count lives in
    // this handler rather than a second one that would replace it
    fg.onEngineTick(function () {
      ticksSinceStop++;
      setSpinnerState('nd_netmap-running');
    });

    // labels draw above this zoom
    const LABEL_ZOOM = +(map.dataset.ndLabelZoom || 0.9);
    const LABEL_SIZE = +(map.dataset.ndLabelSize || 8);
    // read once, not once per node per frame
    const showips = document.getElementById('nd_showips');

    fg.nodeCanvasObjectMode(function () {
      return 'after';
    }).nodeCanvasObject(function (n, ctx, scale) {
      if (n.selected) {
        ctx.beginPath();
        ctx.arc(n.x, n.y, n.radius + 2, 0, 2 * Math.PI);
        ctx.strokeStyle = '#0d6efd';
        ctx.lineWidth = 1.5 / scale;
        ctx.stroke();
      }
      if (scale < LABEL_ZOOM) {
        return;
      }
      ctx.textAlign = 'center';
      ctx.textBaseline = 'top';
      ctx.fillStyle = '#333';

      // Drawn from the two fields rather than splitting LABEL: a device name
      // may contain spaces, and a two-word split drops the rest of it.
      const gap = LABEL_SIZE * 0.5; // graph units, so it holds as the map zooms
      ctx.font = 'bold ' + LABEL_SIZE + 'px sans-serif';
      ctx.fillText(n.ORIG_LABEL, n.x, n.y + n.radius + gap);

      if (showips instanceof HTMLInputElement && showips.checked && n.ORIG_LABEL !== n.ID) {
        ctx.font = LABEL_SIZE + 'px sans-serif';
        ctx.fillText(n.ID, n.x, n.y + n.radius + gap + LABEL_SIZE + 1);
      }
    });

    // read once, not once per link per frame
    const showspeed = document.getElementById('nd_showspeed');
    fg.linkCanvasObjectMode(function () {
      return 'after';
    }).linkCanvasObject(function (l, ctx) {
      if (!(showspeed instanceof HTMLInputElement) || !showspeed.checked) {
        return;
      }
      if (typeof l.source !== 'object') {
        return;
      }
      ctx.font = (map.dataset.ndLinkLabelSize || 5) + 'px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = 'black';
      ctx.fillText(l.SPEED, (l.source.x + l.target.x) / 2, (l.source.y + l.target.y) / 2);
    });

    // the old renderer's legend included ROOTNODE (its distinctNodeColorValues
    // list has no special case for it); '__plain' stays excluded, but it is
    // unreachable here anyway, since the legend only renders for colorby=hgroup
    // or colorby=lgroup, and both always give every node a COLORVALUE (falling
    // back to 'Other' rather than leaving it unset)
    const legend = document.getElementById('nd2_netmap-legend');
    if (legend) {
      // Object.keys is arrival order in the payload, and a long unsorted list in
      // a scroller cannot be read by eye
      Object.keys(colorOf)
        .sort(function (a, b) {
          return a.toLowerCase().localeCompare(b.toLowerCase());
        })
        .forEach(function (key) {
          if (key === '__plain') {
            return;
          }
          const row = document.createElement('div');
          // the row clips to one line, and long site codes share their leading
          // 80 characters, so the title is the only way to tell those rows apart
          row.title = key;
          // colorOf values come from the fixed COLOR10 palette, never from data
          // eslint-disable-next-line no-unsanitized/property
          row.innerHTML = '<span style="color:' + colorOf[key] + '">&#9632;</span> ';
          row.appendChild(document.createTextNode(key));
          legend.appendChild(row);
        });
    }
  });

  // ***********************************************
  // ************ full screen handling *************
  // ***********************************************

  // Safari shipped the unprefixed Fullscreen API in 16.4 (2023); these
  // fallbacks are for older releases still in the field. Neither
  // lib.dom.d.ts nor the type checker's declarations carry the vendor-prefixed
  // members, so the two casts below name them locally instead of widening
  // document or elt themselves to any.
  /**
   * @typedef {object} VendorFullscreenDocument
   * @property {Element} [webkitFullscreenElement]
   * @property {Element} [mozFullScreenElement]
   * @property {Function} [msExitFullscreen]
   * @property {Function} [mozCancelFullScreen]
   * @property {Function} [webkitExitFullscreen]
   */
  /**
   * @typedef {object} VendorFullscreenElement
   * @property {Function} [msRequestFullscreen]
   * @property {Function} [mozRequestFullScreen]
   * @property {Function} [webkitRequestFullscreen]
   */

  /**
   * Reports the element currently shown fullscreen, checking the vendor-prefixed
   * properties before the standard one.
   * @returns {Element|null} the fullscreen element, or null when nothing is fullscreen
   */
  function isFullScreen() {
    const doc = /** @type {Document & VendorFullscreenDocument} */ (document);
    return doc.webkitFullscreenElement || doc.mozFullScreenElement || doc.fullscreenElement;
  }

  /**
   * Toggles fullscreen for elt: exits fullscreen if anything is currently fullscreen,
   * otherwise requests it on elt, trying the vendor-prefixed methods before the
   * standard one.
   * @param {HTMLElement} elt the element to show fullscreen
   * @returns {void}
   */
  function requestFullScreen(elt) {
    const doc = /** @type {Document & VendorFullscreenDocument} */ (document);
    const el = /** @type {HTMLElement & VendorFullscreenElement} */ (elt);
    if (isFullScreen()) {
      if (doc.exitFullscreen) {
        doc.exitFullscreen();
      } else if (doc.msExitFullscreen) {
        doc.msExitFullscreen();
      } else if (doc.mozCancelFullScreen) {
        doc.mozCancelFullScreen();
      } else if (doc.webkitExitFullscreen) {
        doc.webkitExitFullscreen();
      }
    } else {
      if (el.requestFullscreen) {
        el.requestFullscreen();
      } else if (el.msRequestFullscreen) {
        el.msRequestFullscreen();
      } else if (el.mozRequestFullScreen) {
        el.mozRequestFullScreen();
      } else if (el.webkitRequestFullscreen) {
        el.webkitRequestFullscreen();
      }
    }
  }
}
