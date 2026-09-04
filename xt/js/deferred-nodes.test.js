// Coverage for share/public/javascripts/netdisco-deferred-nodes.js.
//
// htmx sets its `once` flag when the click fires, before the request is sent,
// and never clears it, so the retry cannot go back through the trigger. Why it
// goes through htmx.ajax with the box as source is commented at the call site.

'use strict';

const { describe, test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const listeners = {};
const ajaxCalls = [];

const capture = {};
globalThis.document = {
  addEventListener(name, fn, useCapture) {
    listeners[name] = fn;
    capture[name] = useCapture === true;
  },
};
globalThis.window = {
  htmx: { ajax(verb, url, opts) { ajaxCalls.push({ verb, url, opts }); } },
};

require(path.join(__dirname, '..', '..',
  'share', 'public', 'javascripts', 'netdisco-deferred-nodes.js'));

function makeBox(attrs) {
  const classes = new Set(['nd_collapsing', 'nd_nodes-deferred']);
  const box = {
    innerHTML: '<span class="htmx-indicator"></span>',
    classList: {
      contains: (c) => classes.has(c),
      add: (c) => classes.add(c),
    },
    getAttribute: (name) => (attrs || {})[name],
    matches: (sel) => sel === '.nd_nodes-deferred',
    closest: (sel) => (sel === '.nd_nodes-deferred' ? box : null),
    // the handler decides "already loaded" by the indicator being swapped away
    querySelector: (sel) =>
      (sel === '.htmx-indicator' && /htmx-indicator/.test(box.innerHTML) ? {} : null),
  };
  return box;
}

// A Show click reaches the box through the row, not through the box itself:
// the opener is inside .nd_nodes-total and the box is that div's next sibling.
function makeOpener(box) {
  const total = { nextElementSibling: box };
  const opener = { closest: (sel) => (sel === '.nd_nodes-total' ? total : null) };
  return { closest: (sel) => (sel === '.nd_nodes-retry' ? null : opener) };
}

beforeEach(() => { ajaxCalls.length = 0; });

describe('registration', () => {
  // The collapser rewrites the opener's innerHTML in its own click handler, so a
  // bubbling listener receives a click on the plus icon already orphaned from
  // the document, and closest() then finds nothing. Capture runs first.
  test('deferredNodes__the_click_listener__is_registered_on_capture', () => {
    assert.equal(capture.click, true);
  });

  test('deferredNodes__loaded__listens_for_both_htmx_failure_events', () => {
    assert.deepStrictEqual(
      Object.keys(listeners).sort(),
      ['click', 'htmx:responseError', 'htmx:sendError']);
  });
});

describe('failure message', () => {
  test('deferredNodes__responseError_on_a_deferred_box__writes_a_retry_link', () => {
    const box = makeBox();
    listeners['htmx:responseError']({ target: box });
    assert.match(box.innerHTML, /nd_nodes-retry/);
  });

  test('deferredNodes__sendError_on_a_deferred_box__writes_a_retry_link', () => {
    const box = makeBox();
    listeners['htmx:sendError']({ target: box });
    assert.match(box.innerHTML, /nd_nodes-retry/);
  });

  // The spinner is inside the swap region, so the failure message has to put it
  // back or a retry runs with no indicator at all.
  test('deferredNodes__a_failure_message__still_carries_the_spinner', () => {
    const box = makeBox();
    listeners['htmx:responseError']({ target: box });
    assert.match(box.innerHTML,
      /<span class="htmx-indicator"><i class="fas fa-spinner fa-spin"><\/i> Waiting for results\.\.\.<\/span>/);
  });

  test('deferredNodes__an_error_on_an_unrelated_element__is_ignored', () => {
    const other = { innerHTML: 'untouched', matches: () => false };
    listeners['htmx:responseError']({ target: other });
    assert.equal(other.innerHTML, 'untouched');
  });
});

describe('retry', () => {
  test('deferredNodes__clicking_retry__reissues_the_boxs_own_request', () => {
    const box = makeBox({ 'hx-get': '/ajax/content/device/port/nodes?q=1.2.3.4&port=Gi1%2F1' });
    const link = { closest: (sel) => (sel === '.nd_nodes-retry' ? link : box) };
    let defaulted = false;
    listeners.click({ target: link, preventDefault() { defaulted = true; } });

    assert.equal(defaulted, true, 'the anchor must not navigate');
    assert.equal(ajaxCalls.length, 1);
    assert.equal(ajaxCalls[0].verb, 'GET');
    assert.equal(ajaxCalls[0].url,
      '/ajax/content/device/port/nodes?q=1.2.3.4&port=Gi1%2F1');
  });

  test('deferredNodes__a_retry__passes_the_box_as_the_request_source', () => {
    const box = makeBox({ 'hx-get': '/x' });
    const link = { closest: (sel) => (sel === '.nd_nodes-retry' ? link : box) };
    listeners.click({ target: link, preventDefault() {} });
    assert.equal(ajaxCalls[0].opts.source, box);
  });

  test('deferredNodes__a_retry_while_a_request_is_in_flight__is_dropped', () => {
    const box = makeBox({ 'hx-get': '/x' });
    box.classList.add('htmx-request');
    const link = { closest: (sel) => (sel === '.nd_nodes-retry' ? link : box) };
    listeners.click({ target: link, preventDefault() {} });
    assert.equal(ajaxCalls.length, 0);
  });

  test('deferredNodes__clicking_show_on_an_unloaded_box__fetches_it', () => {
    const box = makeBox({ 'hx-get': '/x' });
    listeners.click({ target: makeOpener(box), preventDefault() {} });
    assert.equal(ajaxCalls.length, 1);
    assert.equal(ajaxCalls[0].opts.source, box);
  });

  // htmx binds a trigger once, to the rows in the DOM at the time, and
  // DataTables holds only the current page. Delegation is what makes a box on
  // any other page work at all, so the click must not need the box itself.
  test('deferredNodes__clicking_show_twice__fetches_only_once', () => {
    const box = makeBox({ 'hx-get': '/x' });
    const opener = makeOpener(box);
    listeners.click({ target: opener, preventDefault() {} });
    box.innerHTML = '<div>a node</div>';
    listeners.click({ target: opener, preventDefault() {} });
    assert.equal(ajaxCalls.length, 1, 'a loaded box must not refetch on reopen');
  });

  test('deferredNodes__reopening_a_box_that_failed__tries_again', () => {
    const box = makeBox({ 'hx-get': '/x' });
    listeners['htmx:responseError']({ target: box });
    listeners.click({ target: makeOpener(box), preventDefault() {} });
    assert.equal(ajaxCalls.length, 1);
    assert.doesNotMatch(box.innerHTML, /nd_nodes-retry/);
  });

  test('deferredNodes__clicking_anything_else__issues_no_request', () => {
    listeners.click({ target: { closest: () => null }, preventDefault() {} });
    assert.equal(ajaxCalls.length, 0);
  });

  test('deferredNodes__a_retry__clears_the_failure_message_before_requesting', () => {
    const box = makeBox({ 'hx-get': '/x' });
    const link = { closest: (sel) => (sel === '.nd_nodes-retry' ? link : box) };
    listeners['htmx:responseError']({ target: box });
    assert.match(box.innerHTML, /nd_nodes-retry/);

    listeners.click({ target: link, preventDefault() {} });
    assert.doesNotMatch(box.innerHTML, /nd_nodes-retry/,
      'a retry in flight must not still claim the load failed');
    assert.match(box.innerHTML,
      /<span class="htmx-indicator"><i class="fas fa-spinner fa-spin"><\/i> Waiting for results\.\.\.<\/span>/);
  });
});
