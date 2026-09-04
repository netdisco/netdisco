// The deferred connected-nodes box consumes its htmx trigger when the click
// fires, before the request is sent, and htmx never clears that flag. Without
// this, a fetch that fails leaves an empty box no further clicking can fill.
(function () {
  'use strict';

  var BOX = '.nd_nodes-deferred';
  var INDICATOR = '<span class="htmx-indicator">' +
    '<i class="fas fa-spinner fa-spin"></i> Waiting for results...</span>';

  function showFailure(box) {
    box.innerHTML = INDICATOR +
      '<span class="text-danger">' +
      '<i class="fas fa-triangle-exclamation"></i>&nbsp; Could not load nodes. ' +
      '<a href="#" class="nd_nodes-retry">Retry</a></span>';
  }

  function onFailure(evt) {
    var box = evt.target;
    if (box && box.matches && box.matches(BOX)) {
      showFailure(box);
    }
  }

  // A loaded box has had the indicator swapped away. A failed one has it back,
  // alongside the message, so reopening a box that failed tries again.
  function load(box) {
    if (box.classList.contains('htmx-request')) { return; }
    if (!box.querySelector('.htmx-indicator')) { return; }

    box.innerHTML = INDICATOR;

    // The box carries hx-trigger="none" because htmx binds its triggers once,
    // to the rows in the DOM at the time, and DataTables holds only the current
    // page. Every other box would never be bound. Delegating from document and
    // asking htmx for the request keeps the box's own hx-target, hx-swap and
    // hx-headers, and an /ajax/ path fetched without X-Requested-With is cached
    // by Dancer as the catch-all route.
    window.htmx.ajax('GET', box.getAttribute('hx-get'), { source: box });
  }

  document.addEventListener('htmx:responseError', onFailure);
  document.addEventListener('htmx:sendError', onFailure);

  // Capture, not bubble. The collapser rewrites the opener's innerHTML on its
  // own click handler, so by the time a bubbling listener runs, a click on the
  // plus icon has been orphaned from the document and closest() finds nothing.
  document.addEventListener('click', function (evt) {
    var link = evt.target.closest('.nd_nodes-retry');
    if (link) {
      evt.preventDefault();
      var failed = link.closest(BOX);
      if (failed) { load(failed); }
      return;
    }

    var opener = evt.target.closest('.nd_collapse-vlans');
    if (!opener) { return; }

    var total = opener.closest('.nd_nodes-total');
    var box = total && total.nextElementSibling;
    if (box && box.matches && box.matches(BOX)) { load(box); }
  }, true);
}());
