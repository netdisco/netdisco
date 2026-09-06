// The deferred connected-nodes box consumes its htmx trigger when the click
// fires, before the request is sent, and htmx never clears that flag. Without
// this, a fetch that fails leaves an empty box no further clicking can fill.
(function () {
  'use strict';

  const BOX = '.nd_nodes-deferred';
  const INDICATOR =
    '<span class="htmx-indicator">' + '<i class="fas fa-spinner fa-spin"></i> Waiting for results...</span>';

  /**
   * Replaces a deferred connected-nodes box's content with a failure message and a
   * retry link.
   * @param {Element} box the .nd_nodes-deferred element whose content is replaced
   * @returns {void}
   */
  function showFailure(box) {
    // every part is a literal, none of it is data
    // eslint-disable-next-line no-unsanitized/property
    box.innerHTML =
      INDICATOR +
      '<span class="text-danger">' +
      '<i class="fas fa-triangle-exclamation"></i>&nbsp; Could not load nodes. ' +
      '<a href="#" class="nd_nodes-retry">Retry</a></span>';
  }

  /**
   * Shows the failure message on a deferred connected-nodes box when its htmx request
   * errors, ignoring the event when it did not originate from such a box.
   * @param {Event} evt the htmx:responseError or htmx:sendError event
   * @returns {void}
   */
  function onFailure(evt) {
    const box = /** @type {Element|null} */ (evt.target);
    if (box && box.matches && box.matches(BOX)) {
      showFailure(box);
    }
  }

  /**
   * Fetches a deferred connected-nodes box's content over htmx, unless it is already
   * loading or has already loaded. A loaded box has had the indicator swapped away; a
   * failed one has it back, alongside the failure message, so reopening a box that
   * failed tries again.
   * @param {Element} box the .nd_nodes-deferred element to load
   * @returns {void}
   */
  function load(box) {
    if (box.classList.contains('htmx-request')) {
      return;
    }
    if (!box.querySelector('.htmx-indicator')) {
      return;
    }

    // every part is a literal, none of it is data
    // eslint-disable-next-line no-unsanitized/property
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

  document.addEventListener(
    'click',
    /**
     * Loads a deferred connected-nodes box on a retry-link or collapse-toggle click.
     * Bound on capture, not bubble, because the collapser rewrites the opener's
     * innerHTML in its own click handler, so by the time a bubbling listener would
     * run, a click on the plus icon has been orphaned from the document and
     * closest() finds nothing.
     * @param {MouseEvent} evt the click event
     * @returns {void}
     */
    function (evt) {
      const target = /** @type {Element} */ (evt.target);
      const link = target.closest('.nd_nodes-retry');
      if (link) {
        evt.preventDefault();
        const failed = link.closest(BOX);
        if (failed) {
          load(failed);
        }
        return;
      }

      const opener = target.closest('.nd_collapse-vlans');
      if (!opener) {
        return;
      }

      const total = opener.closest('.nd_nodes-total');
      const box = total && total.nextElementSibling;
      if (box && box.matches && box.matches(BOX)) {
        load(box);
      }
    },
    true
  );
})();
