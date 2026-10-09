// The Native VLAN picker's logic, exercised without a DOM. Like the typeahead's,
// it is a set of pure functions for the reason that CI runs node --test with no
// jsdom, so anything that needs an element can only be covered by the harness.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ROOT = path.join(__dirname, '..', '..');
const FILE = path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco-vlanpicker.js');
const source = fs.readFileSync(FILE, 'utf8');

// Load the shipped file with just enough of a window for its top level to run.
// It does not read ndTypeahead until a field takes focus, so none is supplied.
function loadCore() {
  const win = { addEventListener() {}, document: { addEventListener() {} } };
  const sandbox = { window: win, document: win.document };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  assert.ok(win.ndVlanPicker, 'the file did not publish window.ndVlanPicker');
  return win.ndVlanPicker;
}

const ROWS = [
  { label: 'office', value: '10' },
  { label: 'Voice 100', value: '100' },
  { label: 'guest', value: '200' },
];

test('filterRows__an_empty_term__keeps_every_row', () => {
  assert.deepEqual(loadCore().filterRows(ROWS, ''), ROWS);
});

// Only the label is searched, so "100" finds the voice VLAN because its name
// holds those digits, not because of its number.
test('filterRows__a_term_inside_a_label__keeps_the_rows_that_hold_it', () => {
  assert.deepEqual(loadCore().filterRows(ROWS, '100').map((row) => row.value), ['100']);
  assert.deepEqual(loadCore().filterRows(ROWS, 'e').map((row) => row.value), ['10', '100', '200']);
});

test('filterRows__a_term_in_another_case__still_matches', () => {
  assert.deepEqual(loadCore().filterRows(ROWS, 'VOICE').map((row) => row.value), ['100']);
});

test('filterRows__a_term_nothing_holds__leaves_no_rows', () => {
  assert.deepEqual(loadCore().filterRows(ROWS, 'zzz'), []);
});

// The menu matches what the page shows, so a page showing numbers matches
// numbers and does not go looking in names it never displays.
test('filterRows__rows_labelled_by_number__match_on_the_number_only', () => {
  const numbered = [{ label: '10', value: '10' }, { label: '20', value: '20' }];
  assert.deepEqual(loadCore().filterRows(numbered, '2').map((row) => row.value), ['20']);
});

test('labelFor__a_vlan_the_menu_holds__is_its_label', () => {
  assert.equal(loadCore().labelFor(ROWS, '10'), 'office');
});

// Typing a VLAN the device has not reported sets it, so it has no row to ask.
test('labelFor__a_vlan_the_menu_does_not_hold__is_the_number_itself', () => {
  assert.equal(loadCore().labelFor(ROWS, '999'), '999');
});

// A port with no VLAN keeps an empty number, and the field must stay empty.
test('labelFor__no_vlan__is_empty', () => {
  assert.equal(loadCore().labelFor(ROWS, ''), '');
});

test('typedRow__a_vlan_number__is_a_row_for_it', () => {
  assert.deepEqual(loadCore().typedRow('250'), { label: '250', value: '250' });
  assert.deepEqual(loadCore().typedRow(' 250 '), { label: '250', value: '250' });
});

// Enter with nothing typed, or with a name that matched no row, must not send a
// port to a VLAN that does not exist.
test('typedRow__anything_but_a_number__is_no_row', () => {
  const core = loadCore();
  assert.equal(core.typedRow(''), null);
  assert.equal(core.typedRow('office'), null);
  assert.equal(core.typedRow('10x'), null);
  assert.equal(core.typedRow('0'), null);
  assert.equal(core.typedRow('-5'), null);
});

// A VLAN name comes off the device, so it is only ever put into the menu as
// text. The typeahead holds itself to the same rule, and for the same reason.
test('vlanPicker__its_menu__never_assigns_innerHTML', () => {
  const offenders = source.split('\n')
    .map((line, i) => [i + 1, line])
    .filter(([, line]) => /\.innerHTML\s*=/.test(line) && !/^\s*\/\//.test(line));
  assert.deepEqual(offenders, [],
    'a label reaching the menu as markup is how a VLAN name becomes script');
});

// Bound to the document, not to each field: there is a field in every row of the
// Ports table, and the table is rebuilt on every search.
test('vlanPicker__its_listeners__are_delegated_from_the_document', () => {
  for (const type of ['focusin', 'focusout', 'input', 'keydown', 'click']) {
    assert.match(source, new RegExp("document\\.addEventListener\\(\\s*'" + type + "'"),
      'nothing listens for ' + type + ' on the document');
  }
});

test('vlanPicker__its_menu_element__is_created_once', () => {
  const creations = source.match(/createElement\(\s*'ul'\s*\)/g) || [];
  assert.equal(creations.length, 1, 'more than one place builds a menu');
});
