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

globalThis.document = {
  addEventListener(name, fn) { listeners[name] = fn; },
};
globalThis.window = {
  htmx: { ajax(verb, url, opts) { ajaxCalls.push({ verb, url, opts }); } },
};

require(path.join(__dirname, '..', '..',
  'share', 'public', 'javascripts', 'netdisco-deferred-nodes.js'));

function makeBox(attrs) {
  const classes = new Set(['nd_collapsing', 'nd_nodes-deferred']);
  const box = {
    innerHTML: '',
    classList: {
      contains: (c) => classes.has(c),
      add: (c) => classes.add(c),
    },
    getAttribute: (name) => (attrs || {})[name],
    matches: (sel) => sel === '.nd_nodes-deferred',
    closest: (sel) => (sel === '.nd_nodes-deferred' ? box : null),
  };
  return box;
}

beforeEach(() => { ajaxCalls.length = 0; });

describe('registration', () => {
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
