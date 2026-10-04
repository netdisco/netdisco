'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('share/views/plugin/ClassicColors/ClassicColors.js', 'utf8');
const flush = () => new Promise(resolve => setImmediate(resolve));
function setup() {
  const listeners = {}, requests = [], attrs = {};
  class Element { closest(selector) { return selector.startsWith('#nd-appearance-form button') ? button : form; } }
  class HTMLElement extends Element {}
  const status = {textContent: ''}, input = {checked: true}, csrf = {value: 'session-token'};
  const button = new Element(); button.disabled = false;
  const form = new HTMLElement(); form.id = 'nd-appearance-form'; form.dataset = {action: '/t/demo/ajax/control/admin/appearance/save'};
  form.querySelector = selector => selector.includes('button') ? button : selector.includes('status') ? status : selector.includes('csrf') ? csrf : input;
  const document = {hidden: false, body: {dataset: {ndUriBase: '/t/demo'}}, documentElement: {
    setAttribute: (key, value) => attrs[key] = value,
    removeAttribute: key => delete attrs[key]
  }, addEventListener: (name, callback) => listeners[name] = callback};
  let poll;
  vm.runInNewContext(source, {document, Element, HTMLElement, URLSearchParams,
    setInterval: callback => poll = callback,
    fetch: (url, options) => new Promise(resolve => requests.push({url, options, resolve}))});
  return {requests, attrs, status, button, input, document, poll: () => poll(),
    click: () => listeners.click({target: button, preventDefault() {}, stopPropagation() {}})};
}
const answer = (request, state, ok = true) => request.resolve({ok, json: async () => ({classic_colors: state})});
test('authenticated initial read respects tenant URL and applies current server state', async () => {
  const ui = setup();
  assert.equal(ui.requests[0].url, '/t/demo/ajax/appearance');
  assert.equal(ui.requests[0].options.credentials, 'same-origin');
  answer(ui.requests[0], 1); await flush();
  assert.equal(ui.attrs['data-nd-palette'], 'classic');
  ui.poll(); answer(ui.requests[1], 0); await flush();
  assert.equal(ui.attrs['data-nd-palette'], undefined);
});
test('save sends token and selected state, and stale poll cannot overwrite it', async () => {
  const ui = setup(); ui.click();
  const save = ui.requests[1];
  assert.equal(save.options.method, 'POST');
  assert.equal(save.options.body.get('csrf'), 'session-token');
  assert.equal(save.options.body.get('classic_colors'), '1');
  assert.equal(ui.button.disabled, true);
  answer(save, 1); await flush();
  answer(ui.requests[0], 0); await flush();
  assert.equal(ui.attrs['data-nd-palette'], 'classic');
  assert.equal(ui.status.textContent, 'Saved for everyone.');
  assert.equal(ui.button.disabled, false);
});
test('failed save preserves applied palette and offers retry', async () => {
  const ui = setup(); answer(ui.requests[0], 1); await flush();
  ui.input.checked = false; ui.click(); answer(ui.requests[1], 0, false); await flush();
  assert.equal(ui.attrs['data-nd-palette'], 'classic');
  assert.match(ui.status.textContent, /Could not save/);
  assert.equal(ui.button.disabled, false);
});
test('hidden tabs do not poll', async () => {
  const ui = setup(); answer(ui.requests[0], 0); await flush();
  ui.document.hidden = true; ui.poll();
  assert.equal(ui.requests.length, 1);
});
