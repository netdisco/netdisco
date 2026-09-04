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

  document.addEventListener('htmx:responseError', onFailure);
  document.addEventListener('htmx:sendError', onFailure);

  document.addEventListener('click', function (evt) {
    var link = evt.target.closest('.nd_nodes-retry');
    if (!link) { return; }
    evt.preventDefault();

    var box = link.closest(BOX);
    if (!box || box.classList.contains('htmx-request')) { return; }

    box.innerHTML = INDICATOR;

    // Not through the trigger, which is spent. The source element is what keeps
    // hx-target, hx-swap and hx-headers on the retry, and an /ajax/ path fetched
    // without X-Requested-With is cached by Dancer as the catch-all route.
    window.htmx.ajax('GET', box.getAttribute('hx-get'), { source: box });
  });
}());
