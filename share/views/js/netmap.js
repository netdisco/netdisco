// The netmap: force-graph on canvas, fed by the same payload and posting the
// same positions as the d3 renderer it replaced.

var graph;             // accessor object; the harness and device.js use window.graph
var saveMapPositions;  // device.js binds the sidebar Save button to this

$.getJSON('[% uri_for("/ajax/data/device/netmap") | none %]?[% my_query | none %]', function (mapdata) {

  // the netmap fragment reloads in place (do_search's $(target).html()), so
  // this callback runs again while the previous ForceGraph instance's rAF
  // loop is still running; without tearing it down first, its stale
  // onEngineStop fires against the new, still-settling graph through the
  // reassigned global saveMapPositions and can autosave half-settled positions
  if (window.graph && window.graph.fg && typeof window.graph.fg._destructor === 'function') {
    window.graph.fg._destructor();
  }

  // from here the bottom-right spinner carries the signal through layout to
  // settle, so the two never show at once
  var loading = document.getElementById('nd2_netmap-loading');
  if (loading) { loading.remove() }

  var container = document.getElementById('nd2_netmap-container');
  var nodes = mapdata['data']['nodes'];

  // radius = 4 + rank of the node's SIZEVALUE among the distinct values
  // (max 4 + numsizes - 1); this approximates the old renderer's sqrt scale
  // over the SIZEVALUE extent, it does not reproduce it exactly
  var distinct = {};
  nodes.forEach(function (n) { distinct[n.SIZEVALUE] = true });
  var rankOf = {};
  Object.keys(distinct).map(Number).sort(function (a, b) { return a - b })
    .forEach(function (v, i) { rankOf[v] = i });

  // the ten categorical colors the old renderer's color10 scheme used,
  // assigned per distinct COLORVALUE in first-appearance order
  var COLOR10 = ['#1f77b4', '#ff7f0e', '#2ca02c', '#d62728', '#9467bd',
                 '#8c564b', '#e377c2', '#7f7f7f', '#bcbd22', '#17becf'];
  var colorOf = {}, nextColor = 0;

  nodes.forEach(function (n) {
    var key = ('COLORVALUE' in n) ? String(n.COLORVALUE) : '__plain';
    if (!(key in colorOf)) { colorOf[key] = COLOR10[nextColor++ % 10] }
    n.color = colorOf[key];
    n.radius = 4 + (rankOf[n.SIZEVALUE] || 0);
    if (n.fixed) { n.fx = +n.x; n.fy = +n.y; n.x = +n.x; n.y = +n.y }
  });

  // centroid of the payload's stored fixed positions, so unpinned nodes
  // gather around a restored layout instead of splitting off toward the
  // origin, and so the camera below can be pointed at that layout
  var fixedNodes = nodes.filter(function (n) { return n.fixed });
  var cx = 0, cy = 0;
  if (fixedNodes.length) {
    fixedNodes.forEach(function (n) { cx += +n.x; cy += +n.y });
    cx /= fixedNodes.length; cy /= fixedNodes.length;
  }

  // the backend builds links before filtering nodes by group selection, so a
  // link can reference an ID that was filtered out of the node set; force-graph
  // throws mid-simulation on such a dangling reference (the old renderer
  // filtered these out client-side too, d3-force-network-chart.js's "sort out
  // links with invalid node references"), which aborts the paint loop for that
  // tick and leaves nodes drawn only until the next successful repaint (zoom)
  var nodeIds = {};
  nodes.forEach(function (n) { nodeIds[n.ID] = true });
  var links = mapdata['data']['links']
    .filter(function (l) { return (l.FROMID in nodeIds) && (l.TOID in nodeIds) })
    .map(function (l) {
      return { source: l.FROMID, target: l.TOID, SPEED: l.SPEED, INFOSTRING: l.INFOSTRING };
    });

  // force-graph swaps a link's source/target from a plain ID to the node
  // object once it resolves them, so any code touching links after that
  // point has to handle both shapes; one helper for both call sites
  function endpointId(l, end) { var v = l[end]; return (typeof v === 'object') ? v.ID : v }

  // read the template condition once; two handlers below need it
  var autosaveOn = ('[% "on" IF params.autosave == "on" %]' === 'on');

  // force-graph reheats the simulation on every drag event, and once the first
  // layout has finished alpha is already below d3AlphaMin, so the engine stops
  // again at once having run no ticks. Counting ticks is what tells a real
  // settle apart from those, and without it the save below fires once per
  // mousemove, posting the whole map each time.
  var ticksSinceStop = 0;

  var fg = ForceGraph()(container)
    .width(parseInt(jQuery('#netmap_pane').parent().css('width')))
    .height(window.innerHeight - 100)
    .nodeId('ID')
    .nodeRelSize(1)
    .nodeVal(function (n) { return n.radius * n.radius })
    .nodeColor(function (n) { return n.color })
    .nodeLabel(function (n) { return n.INFOSTRING })
    .linkLabel(function (l) { return l.INFOSTRING })
    .linkWidth(2)
    .minZoom(0.1)
    .maxZoom(10)
    .cooldownTime(Infinity)
    .d3AlphaMin(0.001)
    .onNodeDragEnd(function (n) {
      n.fx = n.x; n.fy = n.y; dragSnap = null;
      // the engine stop that follows a drag runs no ticks, so this is the only
      // place a hand-moved node gets persisted; once per drag, not per mousemove
      if (autosaveOn) { saveMapPositions() }
    })
    .onEngineStop(function () {
      document.getElementById('nd2_netmap-spinner').className = 'nd_netmap-settled';
      fg.graphData().nodes.forEach(function (n) { n.fx = n.x; n.fy = n.y });
      var ranTicks = ticksSinceStop;
      ticksSinceStop = 0;
      if (ranTicks && autosaveOn) { saveMapPositions() }
    })
    .graphData({ nodes: nodes, links: links });

  // netdisco maps hold disconnected islands, so pull each node to the middle
  // instead of centering the mean (the old renderer's gravity did the same)
  function ndPull(axis, target, strength) {
    var ns;
    function force(alpha) {
      for (var i = 0; i < ns.length; i++) {
        ns[i]['v' + axis] += (target - ns[i][axis]) * strength * alpha;
      }
    }
    force.initialize = function (init) { ns = init };
    return force;
  }
  fg.d3Force('charge').strength(-550);
  fg.d3Force('link').distance(120);
  fg.d3Force('center', null);
  // force-graph's origin is the viewport center (measured: graph2ScreenCoords(0,0)
  // equals the canvas midpoint), unlike the old SVG renderer's top-left origin,
  // so "the middle" the comment above promises is the stored layout's centroid
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
    fg.graphData().nodes.forEach(function (n) { n.fx = n.x; n.fy = n.y });
    $.post(
      '[% uri_for("/ajax/data/device/netmappositions") | none %]'
      , $("#nd_vlan-entry, #nd_mapshow-hops, #nd_hgroup-select, #nd_lgroup-select, #nq, input[name='mapshow']").serialize()
        + '&positions=' + JSON.stringify(graph.positions())
    ).done(function () {
      if (announce && !autosaveOn) { toastr.success('Saved map positions.') }
    });
  };

  graph = {
    fg: fg,
    centernode: mapdata['centernode'],
    nodeDataById: function (id) {
      var hit = null;
      fg.graphData().nodes.forEach(function (n) { if (n.ID === id) { hit = n } });
      return hit;
    },
    positions: function () {
      return fg.graphData().nodes.map(function (n) {
        return { ID: n.ID, x: Math.round(n.x), y: Math.round(n.y),
                 fixed: (n.fx !== undefined && n.fx !== null) ? 1 : 0 };
      });
    },
    links: function () {
      return fg.graphData().links.map(function (l) {
        return { source: endpointId(l, 'source'), target: endpointId(l, 'target') };
      });
    },
    screenXY: function (id) {
      var n = graph.nodeDataById(id);
      if (!n) { return null }
      var p = fg.graph2ScreenCoords(n.x, n.y);
      var r = container.querySelector('canvas').getBoundingClientRect();
      return { x: r.left + p.x, y: r.top + p.y };
    },
  };
  window.graph = graph;

  // force-graph exposes no simulation find() and no dblclick callback; its
  // own hit detection delivers the node to onNodeClick, so a double click is
  // two clicks on the same node inside the double-click window
  var lastClick = { id: null, at: 0 };
  fg.onNodeClick(function (n) {
    var now = Date.now();
    // 500 ms matches the platform double-click default the old renderer's
    // dblclick event inherited
    if (n.ID === lastClick.id && (now - lastClick.at) < 500) {
      window.location.assign(n.LINK);
      return;
    }
    lastClick = { id: n.ID, at: now };
  });

  fg.linkCurvature(function (l) {
    var s = endpointId(l, 'source'), t = endpointId(l, 'target');
    return (s === t) ? 0.6 : 0;
  });

  // the old template zoomed to the center node 1.5 s after start when
  // mapshow=neighbors (a legacy value still reachable from bookmarks)
  if ('[% params.mapshow | html_entity %]' == 'neighbors') {
    setTimeout(function () {
      var n = graph.nodeDataById(graph.centernode);
      if (n) { fg.centerAt(n.x, n.y, 600); fg.zoom(4, 600) }
    }, 1500);
  }

  // box select: shift-drag replaces the old freehand lasso by ruling.
  // capture-phase listener so force-graph's own pan never sees the drag.
  var box = { active: false, x0: 0, y0: 0, el: null };
  container.addEventListener('pointerdown', function (ev) {
    if (!ev.shiftKey) { return }
    ev.stopPropagation(); ev.preventDefault();
    fg.enablePanInteraction(false).enableZoomInteraction(false);
    box.active = true; box.x0 = ev.clientX; box.y0 = ev.clientY;
    box.el = document.createElement('div');
    box.el.id = 'nd2_netmap-boxselect';
    // document.body sits outside the fullscreen element, so a box drawn
    // there would be invisible while fullscreen; append into whichever is
    // actually showing
    (document.fullscreenElement || document.body).appendChild(box.el);
  }, true);
  function onBoxPointerMove(ev) {
    if (!box.active) { return }
    var x = Math.min(box.x0, ev.clientX), y = Math.min(box.y0, ev.clientY);
    box.el.style.left = x + 'px';
    box.el.style.top = y + 'px';
    box.el.style.width = Math.abs(ev.clientX - box.x0) + 'px';
    box.el.style.height = Math.abs(ev.clientY - box.y0) + 'px';
  }
  function onBoxPointerUp(ev) {
    if (!box.active) { return }
    box.active = false;
    box.el.remove();
    fg.enablePanInteraction(true).enableZoomInteraction(true);
    var r = container.querySelector('canvas').getBoundingClientRect();
    var a = fg.screen2GraphCoords(Math.min(box.x0, ev.clientX) - r.left, Math.min(box.y0, ev.clientY) - r.top);
    var b = fg.screen2GraphCoords(Math.max(box.x0, ev.clientX) - r.left, Math.max(box.y0, ev.clientY) - r.top);
    fg.graphData().nodes.forEach(function (n) {
      n.selected = (n.x >= a.x && n.x <= b.x && n.y >= a.y && n.y <= b.y);
    });
    fg.nodeRelSize(fg.nodeRelSize());
  }
  // raw listeners cannot be namespaced like jQuery's; on a fragment reload,
  // remove the previous render's pair by reference before adding this one,
  // or they accumulate on window forever
  if (window.__ndNetmapPointerHandlers) {
    window.removeEventListener('pointermove', window.__ndNetmapPointerHandlers.move);
    window.removeEventListener('pointerup', window.__ndNetmapPointerHandlers.up);
  }
  window.__ndNetmapPointerHandlers = { move: onBoxPointerMove, up: onBoxPointerUp };
  window.addEventListener('pointermove', onBoxPointerMove);
  window.addEventListener('pointerup', onBoxPointerUp);

  // dragging one selected node carries the rest of the selection
  var dragSnap = null;
  fg.onNodeDrag(function (n, translate) {
    if (!n.selected) { return }
    if (!dragSnap) {
      // hold the node objects themselves, not their IDs: an ID-keyed lookup
      // means a linear nodeDataById() scan per node per tick, and re-keying
      // by ID risks the numeric-vs-string coercion Object.keys() does
      dragSnap = [];
      fg.graphData().nodes.forEach(function (o) {
        if (o.selected && o.ID !== n.ID) { dragSnap.push({ node: o, x: o.x, y: o.y }) }
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
  document.getElementById('nd2_netmap-fullscreen').addEventListener('click', function () {
    requestFullScreen(document.getElementById('netmap_pane'));
  });
  // namespaced so a fragment reload's .off() removes only this render's
  // handler instead of every handler ever bound to these shared elements
  $(document).off('.ndnetmap').on('webkitfullscreenchange.ndnetmap mozfullscreenchange.ndnetmap fullscreenchange.ndnetmap', function () {
    resizeGraphContainer();
    $('#nd2_netmap-fullscreen i').attr('class',
      isFullScreen() ? 'fas fa-compress fa-lg' : 'fas fa-expand fa-lg');
  });

  function resizeGraphContainer() {
    setTimeout(function () {
      fg.width(parseInt(jQuery('#netmap_pane').parent().css('width')))
        .height(window.innerHeight - 100);
    }, 500);
  }
  $('#nd_sidebar-toggle-img-in').off('.ndnetmap').on('click.ndnetmap', resizeGraphContainer);
  $('#nd_sidebar-toggle-img-out').off('.ndnetmap').on('click.ndnetmap', resizeGraphContainer);
  $(window).off('resize.ndnetmap').on('resize.ndnetmap', resizeGraphContainer);

  // onEngineTick is a setter, not a subscription, so the tick count lives in
  // this handler rather than a second one that would replace it
  fg.onEngineTick(function () {
    ticksSinceStop++;
    var el = document.getElementById('nd2_netmap-spinner');
    if (el.className !== 'nd_netmap-running') { el.className = 'nd_netmap-running' }
  });

  // labels draw above this zoom
  var LABEL_ZOOM = '[% settings.netmap.node_label_zoom_threshold || 0.9 %]';

  fg.nodeCanvasObjectMode(function () { return 'after' })
    .nodeCanvasObject(function (n, ctx, scale) {
      if (n.selected) {
        ctx.beginPath();
        ctx.arc(n.x, n.y, n.radius + 2, 0, 2 * Math.PI);
        ctx.strokeStyle = '#0d6efd';
        ctx.lineWidth = 1.5 / scale;
        ctx.stroke();
      }
      if (scale < LABEL_ZOOM) { return }
      ctx.font = 'bold [% settings.netmap.node_label_font_size || 8 %]px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'top';
      ctx.fillStyle = '#333';
      var lineheight = ('[% settings.netmap.node_label_font_size || 8 %]' / scale) * 1.2;
      var words = String(n.LABEL).split(/\s+/);
      ctx.fillText(words[0], n.x, n.y - (lineheight / 2) + n.radius + lineheight);
      ctx.font = '[% settings.netmap.node_label_font_size || 8 %]px sans-serif';
      if (words.length > 1) {
          ctx.fillText(words[1], n.x, n.y + (lineheight / 2) + n.radius + '[% settings.netmap.node_label_font_size || 8 %]' + 1);
      }
    });

  // read once, not once per link per frame
  var showspeed = document.getElementById('nd_showspeed');
  fg.linkCanvasObjectMode(function () { return 'after' })
    .linkCanvasObject(function (l, ctx) {
      if (!showspeed || !showspeed.checked) { return }
      if (typeof l.source !== 'object') { return }
      ctx.font = '[% settings.netmap.link_label_font_size || 5 %]px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = 'black';
      ctx.fillText(l.SPEED, (l.source.x + l.target.x) / 2, (l.source.y + l.target.y) / 2);
    });

  // the old renderer's legend included ROOTNODE (its distinctNodeColorValues
  // list has no special case for it); '__plain' stays excluded, but it is
  // unreachable here anyway, since the legend only renders for colorby=hgroup
  // or colorby=lgroup, and both always give every node a COLORVALUE (falling
  // back to 'Other' rather than leaving it unset)
  var legend = document.getElementById('nd2_netmap-legend');
  if (legend) {
    // Object.keys is arrival order in the payload; the old renderer sorted
    // its legend, and 3152 unsorted rows in a scroller cannot be read by eye
    Object.keys(colorOf).sort(function (a, b) {
      return a.toLowerCase().localeCompare(b.toLowerCase());
    }).forEach(function (key) {
      if (key === '__plain') { return }
      var row = document.createElement('div');
      // the row clips to one line, and long site codes share their leading
      // 80 characters, so the title is the only way to tell those rows apart
      row.title = key;
      row.innerHTML = '<span style="color:' + colorOf[key] + '">&#9632;</span> ';
      row.appendChild(document.createTextNode(key));
      legend.appendChild(row);
    });
  }
});

// ***********************************************
// ************ full screen handling *************
// ***********************************************

function isFullScreen() {
  return (document.webkitFullscreenElement || document.mozFullScreenElement || document.fullscreenElement);
}

function requestFullScreen(elt) {
  if (isFullScreen()) {
    if (document.exitFullscreen) {
      document.exitFullscreen();
    } else if (document.msExitFullscreen) {
      document.msExitFullscreen();
    } else if (document.mozCancelFullScreen) {
      document.mozCancelFullScreen();
    } else if (document.webkitExitFullscreen) {
      document.webkitExitFullscreen();
    }
  }
  else {
    if (elt.requestFullscreen) {
      elt.requestFullscreen();
    } else if (elt.msRequestFullscreen) {
      elt.msRequestFullscreen();
    } else if (elt.mozRequestFullScreen) {
      elt.mozRequestFullScreen();
    } else if (elt.webkitRequestFullscreen) {
      elt.webkitRequestFullscreen();
    }
  }
}
