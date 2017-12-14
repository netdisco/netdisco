importScripts( 'http://localhost:5000/javascripts/d3-3.5.6.js' );

onmessage = function(event) {
  var force = event.data.force;

  for (var i = 0, n = Math.ceil(Math.log(0.001) / Math.log(1 - (1 - Math.pow(0.001, 1 / 300)))); i < n; ++i) {
    postMessage({type: "tick", progress: i / n});
    force.tick();
  }

  postMessage({type: "end", force: force});
};
