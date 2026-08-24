// The netmap: force-graph on canvas, fed by the same payload and posting the
// same positions as the d3 renderer it replaced.

var graph;             // accessor object; the harness and device.js use window.graph
var saveMapPositions;  // device.js binds the sidebar Save button to this

$.getJSON('[% uri_for("/ajax/data/device/netmap") | none %]?[% my_query | none %]', function (mapdata) {

  var container = document.getElementById('nd2_netmap-container');
  var nodes = mapdata['data']['nodes'];

  // radius = 4 + rank of the node's SIZEVALUE among the distinct values,
  // reproducing minNodeRadius(4) / maxNodeRadius(4 + numsizes)
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

  var links = mapdata['data']['links'].map(function (l) {
    return { source: l.FROMID, target: l.TOID, SPEED: l.SPEED, INFOSTRING: l.INFOSTRING };
  });

  var fg = ForceGraph()(container)
    .width(parseInt(jQuery('#netmap_pane').parent().css('width')))
    .height(window.innerHeight - 100)
    .nodeId('ID')
    .nodeRelSize(1)
    .nodeVal(function (n) { return n.radius * n.radius })
    .nodeColor(function (n) { return n.color })
    .nodeLabel(function (n) { return n.INFOSTRING })
    .linkLabel(function (l) { return l.INFOSTRING })
    .minZoom(0.1)
    .maxZoom(10)
    .cooldownTime(Infinity)
    .d3AlphaMin(0.001)
    .onNodeDragEnd(function (n) { n.fx = n.x; n.fy = n.y; dragSnap = null })
    .onEngineStop(function () {
      document.getElementById('nd2_netmap-spinner').className = 'nd_netmap-settled';
      fg.graphData().nodes.forEach(function (n) { n.fx = n.x; n.fy = n.y });
      if ('[% "on" IF params.autosave == "on" %]' === 'on') { saveMapPositions(); }
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

  saveMapPositions = function () {
    fg.graphData().nodes.forEach(function (n) { n.fx = n.x; n.fy = n.y });
    $.post(
      '[% uri_for("/ajax/data/device/netmappositions") | none %]'
      , $("#nd_vlan-entry, #nd_mapshow-hops, #nd_hgroup-select, #nd_lgroup-select, #nq, input[name='mapshow']").serialize()
        + '&positions=' + JSON.stringify(graph.positions())
    );
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
        return { source: (typeof l.source === 'object' ? l.source.ID : l.source),
                 target: (typeof l.target === 'object' ? l.target.ID : l.target) };
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
    if (n.ID === lastClick.id && (now - lastClick.at) < 400) {
      window.location.assign(n.LINK);
      return;
    }
    lastClick = { id: n.ID, at: now };
  });

  fg.linkCurvature(function (l) {
    var s = (typeof l.source === 'object') ? l.source.ID : l.source;
    var t = (typeof l.target === 'object') ? l.target.ID : l.target;
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
    document.body.appendChild(box.el);
  }, true);
  window.addEventListener('pointermove', function (ev) {
    if (!box.active) { return }
    var x = Math.min(box.x0, ev.clientX), y = Math.min(box.y0, ev.clientY);
    box.el.style.left = x + 'px';
    box.el.style.top = y + 'px';
    box.el.style.width = Math.abs(ev.clientX - box.x0) + 'px';
    box.el.style.height = Math.abs(ev.clientY - box.y0) + 'px';
  });
  window.addEventListener('pointerup', function (ev) {
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
  });

  // dragging one selected node carries the rest of the selection
  var dragSnap = null;
  fg.onNodeDrag(function (n, translate) {
    if (!n.selected) { return }
    if (!dragSnap) {
      dragSnap = {};
      fg.graphData().nodes.forEach(function (o) {
        if (o.selected && o.ID !== n.ID) { dragSnap[o.ID] = { x: o.x, y: o.y } }
      });
    }
    // translate is the per-tick incremental delta, not cumulative from drag
    // start, so the snapshot itself has to accumulate it tick by tick
    Object.keys(dragSnap).forEach(function (id) {
      var o = graph.nodeDataById(id);
      dragSnap[id].x += translate.x;
      dragSnap[id].y += translate.y;
      o.fx = o.x = dragSnap[id].x;
      o.fy = o.y = dragSnap[id].y;
    });
  });

  // fullscreen: same API dance the old template used, on the pane so the
  // sidebar stays outside it
  document.getElementById('nd2_netmap-fullscreen').addEventListener('click', function () {
    requestFullScreen(document.getElementById('netmap_pane'));
  });
  $(document).on('webkitfullscreenchange mozfullscreenchange fullscreenchange', function () {
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
  $('#nd_sidebar-toggle-img-in').on('click', resizeGraphContainer);
  $('#nd_sidebar-toggle-img-out').on('click', resizeGraphContainer);
  $(window).on('resize', resizeGraphContainer);

  fg.onEngineTick(function () {
    var el = document.getElementById('nd2_netmap-spinner');
    if (el.className !== 'nd_netmap-running') { el.className = 'nd_netmap-running' }
  });

  var LABEL_ZOOM = 1.5;   // labels draw above this zoom; tune by eye against master
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
      ctx.font = '4px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'top';
      ctx.fillStyle = '#333';
      var words = String(n.LABEL).split(/\s+/), line = '', lines = [];
      words.forEach(function (w) {
        if ((line + ' ' + w).trim().length > 16) { lines.push(line.trim()); line = w }
        else { line = line + ' ' + w }
      });
      lines.push(line.trim());
      lines.forEach(function (txt, i) {
        ctx.fillText(txt, n.x, n.y + n.radius + 2 + i * 4.5);
      });
    });

  fg.linkCanvasObjectMode(function () { return 'after' })
    .linkCanvasObject(function (l, ctx) {
      if (!document.getElementById('nd_showspeed').checked) { return }
      if (typeof l.source !== 'object') { return }
      ctx.font = '4px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = 'black';
      ctx.fillText(l.SPEED, (l.source.x + l.target.x) / 2, (l.source.y + l.target.y) / 2);
    });

  var legend = document.getElementById('nd2_netmap-legend');
  if (legend) {
    Object.keys(colorOf).forEach(function (key) {
      if (key === '__plain' || key === 'ROOTNODE') { return }
      var row = document.createElement('div');
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
