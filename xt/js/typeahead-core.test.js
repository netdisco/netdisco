// The typeahead's logic, exercised without a DOM. Everything here is a pure
// function of its arguments, which is the reason the component is split this
// way: CI runs node --test with no jsdom, so anything that needs an element
// can only be covered by the harness.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ROOT = path.join(__dirname, '..', '..');
const source = fs.readFileSync(
  path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco-typeahead.js'), 'utf8');

// Load the shipped file with just enough of a window for its top level to run.
// Anything the DOM layer needs at load time is a bug: the core must be usable
// before there is a document.
function loadCore() {
  const win = { addEventListener() {}, document: { addEventListener() {} } };
  const sandbox = { window: win, document: win.document, jQuery: undefined };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  assert.ok(win.ndTypeahead, 'the file did not publish window.ndTypeahead');
  return win.ndTypeahead;
}

// A stand-in for an element, carrying only what readOptions reads.
const withAttributes = (attrs) => ({
  getAttribute: (name) => (name in attrs ? attrs[name] : null),
  hasAttribute: (name) => name in attrs,
});

test('readOptions__a_field_with_only_a_url__defaults_the_rest', () => {
  const core = loadCore();
  const options = core.readOptions(withAttributes({
    'data-nd-typeahead': '/ajax/data/subnet/typeahead' }));
  assert.equal(options.url, '/ajax/data/subnet/typeahead');
  assert.equal(options.min, 0);
  assert.equal(options.params, null);
  assert.equal(options.opensOnFocus, false);
  assert.equal(options.first, false);
});

// The distinction the whole request contract turns on: an empty attribute
// value still means "open on focus", and only its presence says so.
test('readOptions__an_empty_open_attribute__still_opens_on_focus', () => {
  const core = loadCore();
  const options = core.readOptions(withAttributes({
    'data-nd-typeahead': '/ajax/data/port/typeahead',
    'data-nd-typeahead-open': '' }));
  assert.equal(options.opensOnFocus, true);
  assert.equal(options.openTerm, '');
});

test('readOptions__a_wildcard_open_attribute__carries_the_wildcard', () => {
  const core = loadCore();
  const options = core.readOptions(withAttributes({
    'data-nd-typeahead': '/ajax/data/deviceip/typeahead',
    'data-nd-typeahead-open': '%' }));
  assert.equal(options.opensOnFocus, true);
  assert.equal(options.openTerm, '%');
});

test('readOptions__a_params_selector_list__is_split_and_trimmed', () => {
  const core = loadCore();
  const options = core.readOptions(withAttributes({
    'data-nd-typeahead': '/ajax/data/devices/typeahead',
    'data-nd-typeahead-params': '.nd_sidebar-form, self' }));
  assert.deepEqual(options.params, ['.nd_sidebar-form', 'self']);
});

test('normalizeRows__an_array_of_strings__becomes_rows_whose_label_is_the_value', () => {
  const core = loadCore();
  assert.deepEqual(core.normalizeRows(['10.0.0.0/8', '10.1.0.0/16']), [
    { label: '10.0.0.0/8', value: '10.0.0.0/8' },
    { label: '10.1.0.0/16', value: '10.1.0.0/16' },
  ]);
});

// The shape that makes the menu show one string and the field keep another.
test('normalizeRows__an_array_of_label_and_value__keeps_them_apart', () => {
  const core = loadCore();
  assert.deepEqual(core.normalizeRows([{ label: 'sw1 (10.0.0.1)', value: '10.0.0.1' }]), [
    { label: 'sw1 (10.0.0.1)', value: '10.0.0.1' },
  ]);
});

test('normalizeRows__anything_that_is_not_a_list__becomes_no_rows', () => {
  const core = loadCore();
  assert.deepEqual(core.normalizeRows(null), []);
  assert.deepEqual(core.normalizeRows({ error: 'nope' }), []);
});

// Highlighting is why the list shows why each row is in it. It is built from
// text nodes rather than markup, so a device name is never parsed as HTML.
test('highlightInto__a_label_containing_the_term__marks_every_occurrence', () => {
  const core = loadCore();
  const node = fakeNode();
  core.highlightInto(node, 'switch-a-switch', 'switch');
  assert.equal(node.textContent, 'switch-a-switch');
  assert.deepEqual(node.marked, ['switch', 'switch']);
});

test('highlightInto__a_term_holding_regex_punctuation__is_matched_literally', () => {
  const core = loadCore();
  const node = fakeNode();
  core.highlightInto(node, 'net 10.0.0.0/8 here', '10.0.0.0/8');
  assert.equal(node.textContent, 'net 10.0.0.0/8 here');
  assert.deepEqual(node.marked, ['10.0.0.0/8']);
});

// A name carrying an ampersand or a tag reaches the menu as text, and stays
// text. This is the assertion that says the renderer never builds markup.
test('highlightInto__a_label_holding_markup__stays_a_single_text_node', () => {
  const core = loadCore();
  const node = fakeNode();
  core.highlightInto(node, 'a&b <script>', '');
  assert.equal(node.textContent, 'a&b <script>');
  assert.deepEqual(node.marked, []);
  assert.equal(node.usedInnerHTML, false);
});

test('nextIndex__from_the_typed_text_going_down__reaches_the_first_row', () => {
  const core = loadCore();
  assert.equal(core.nextIndex(-1, 3, 1), 0);
});

// Walking off the end returns the typed text rather than wrapping.
test('nextIndex__from_the_last_row_going_down__returns_to_the_typed_text', () => {
  const core = loadCore();
  assert.equal(core.nextIndex(2, 3, 1), -1);
});

test('nextIndex__from_the_typed_text_going_up__reaches_the_last_row', () => {
  const core = loadCore();
  assert.equal(core.nextIndex(-1, 3, -1), 2);
});

test('nextIndex__with_no_rows__stays_on_the_typed_text', () => {
  const core = loadCore();
  assert.equal(core.nextIndex(-1, 0, 1), -1);
});

// Records what highlightInto did without a DOM: which strings went into a
// <strong>, and whether the function ever reached for innerHTML.
function fakeNode() {
  const node = {
    textContent: '',
    marked: [],
    usedInnerHTML: false,
    appendChild(child) {
      if (child.tag === 'strong') { node.marked.push(child.textContent); }
      node.textContent += child.textContent;
      return child;
    },
  };
  Object.defineProperty(node, 'innerHTML', {
    set() { node.usedInnerHTML = true; },
    get() { return node.textContent; },
  });
  node.ownerDocument = {
    createTextNode: (text) => ({ tag: '#text', textContent: text }),
    createElement: (tag) => ({
      tag,
      textContent: '',
      appendChild(child) { this.textContent += child.textContent; return child; },
    }),
  };
  return node;
}
