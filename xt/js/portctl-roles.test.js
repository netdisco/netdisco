// Guards the User Management Port Control cell in netdisco-admin.js
// (nd_portctl_render, nd_portctl_change, nd_portctl_remove), which lets an
// admin give a user several port control roles. The select picks a mode or a
// role; each held role is a label whose hidden checkbox is what the row posts
// as portctl_roles.
//
// The rule that matters most: when the last label goes, the select falls back
// to Off, never to "Enabled (any port)". A role-scoped user saved as any port
// can change every port, and an admin removing labels one by one must not
// widen anyone by accident. Off and any port drop every label, including one
// for a role that is no longer defined.
//
// Labels and options are matched by index (data-nd-role), not by role name: a
// role name is admin-entered text, and putting it in a selector broke on
// quotes. CI runs node --test with no jsdom, so this builds only the DOM the
// three functions touch. The cell's markup is tested in xt/222.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const adminSource = fs.readFileSync(
  path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco-admin.js'), 'utf8');

class FakeElement {
  constructor(classes) { this.classes = classes || []; }
  matches(selector) { return this.classes.includes(selector.replace(/^\./, '')); }
  closest(selector) {
    for (let el = this; el; el = el.parent) {
      if (selector === 'tr' ? el.isRow : el.matches(selector)) return el;
    }
    return null;
  }
}

class FakeOption {
  constructor(value, role) {
    this.value = value;
    this.dataset = role === undefined ? {} : { ndRole: role };
    this.disabled = false;
  }
}

// Setting value picks the first option with that value, as a browser does,
// and an unknown value leaves nothing selected.
class FakeSelect extends FakeElement {
  constructor(options, value) {
    super(['nd_portctl_mode']);
    this.options = options;
    this.value = value;
  }
  get value() { return this.selected ? this.selected.value : ''; }
  set value(v) { this.selected = this.options.find((o) => o.value === v) || null; }
  get selectedOptions() { return this.selected ? [this.selected] : []; }
  querySelector(selector) {
    const m = /^option\[data-nd-role="([^"]*)"\]$/.exec(selector);
    assert.ok(m, 'an option is looked up by a well-formed data-nd-role selector: ' + selector);
    return this.options.find((o) => o.dataset.ndRole === m[1]) || null;
  }
}

class FakeChip extends FakeElement {
  constructor(role, value, held) {
    super(['nd_portctl_chip']);
    this.dataset = { ndRole: role };
    this.input = { name: 'portctl_roles', value, checked: held };
    this.hidden = !held;
    this.button = new FakeElement(['nd_portctl_remove']);
    this.button.parent = this;
  }
  querySelector(selector) { return selector === 'input' ? this.input : null; }
}

// One user row as users.tt renders it: listed roles get an option and a label
// each, by index; held roles no longer defined get a label "u<n>" only.
function makeRow({ listed = [], held = [], unlisted = [], mode }) {
  const options = [
    new FakeOption(''),
    new FakeOption('_global_'),
    new FakeOption('_roles_'),
    Object.assign(new FakeOption('──────────'), { disabled: true }),
    ...listed.map((role, i) => new FakeOption(role, String(i))),
  ];
  const chips = [
    ...listed.map((role, i) => new FakeChip(String(i), role, held.includes(role))),
    ...unlisted.map((role, i) => new FakeChip('u' + i, role, true)),
  ];
  const byRole = held.length + unlisted.length > 0;
  const select = new FakeSelect(options, mode !== undefined ? mode : (byRole ? '_roles_' : ''));
  listed.forEach((role, i) => { if (held.includes(role)) options[4 + i].disabled = true; });

  const row = new FakeElement([]);
  row.isRow = true;
  row.querySelectorAll = (sel) => (sel === '.nd_portctl_chip' ? chips : []);
  row.querySelector = (sel) => (sel === '.nd_portctl_mode' ? select : null);
  select.parent = row;
  chips.forEach((chip) => { chip.parent = row; });

  const chip = (role) => chips.find((c) => c.input.value === role);
  const option = (role) => options.find((o) => o.value === role && o.dataset.ndRole !== undefined);
  // what the row would post as portctl_roles: the checked boxes, in order
  const posted = () => chips.filter((c) => c.input.checked).map((c) => c.input.value);
  return { row, select, chips, chip, option, posted };
}

// Loads netdisco-admin.js and hands back its document-level change and click
// listeners, which is how the page reaches the three functions.
function loadAdmin() {
  const listeners = { change: [], click: [] };
  const documentMock = {
    body: { addEventListener: () => {} },
    addEventListener: (name, fn) => { if (listeners[name]) listeners[name].push(fn); },
    getElementById: () => null,
    querySelector: () => null,
  };
  new Function(
    'document', 'window', 'ndPages', 'Element', 'ndRequest', 'ndToast', 'htmx',
    'bootstrap', 'uri_base', 'HTMLElement',
    adminSource,
  )(documentMock, {}, {}, FakeElement, {}, {}, { trigger: () => {} }, {}, '', FakeElement);

  const dispatch = (type, target) => listeners[type].forEach(
    (fn) => fn({ target, preventDefault: () => {} }));
  return {
    dispatch,
    pick(cell, value) {
      cell.select.value = value;
      dispatch('change', cell.select);
    },
    remove(cell, role) { dispatch('click', cell.chip(role).button); },
  };
}

test('portctlChange__picking_a_role__adds_its_label_and_shows_by_role', () => {
  const page = loadAdmin();
  const cell = makeRow({ listed: ['core', 'edge'] });
  page.pick(cell, 'edge');
  assert.strictEqual(cell.select.value, '_roles_');
  assert.deepStrictEqual(cell.posted(), ['edge']);
  assert.strictEqual(cell.chip('edge').hidden, false, 'the label shows');
  assert.strictEqual(cell.chip('core').hidden, true);
  assert.strictEqual(cell.option('edge').disabled, true, 'a held role cannot be picked twice');
  assert.strictEqual(cell.option('core').disabled, false);
});

test('portctlChange__picking_a_second_role__keeps_the_first', () => {
  const page = loadAdmin();
  const cell = makeRow({ listed: ['core', 'edge'], held: ['core'] });
  page.pick(cell, 'edge');
  assert.strictEqual(cell.select.value, '_roles_');
  assert.deepStrictEqual(cell.posted(), ['core', 'edge']);
  assert.strictEqual(cell.option('core').disabled, true);
  assert.strictEqual(cell.option('edge').disabled, true);
});

test('portctlChange__picking_a_role__keeps_an_undefined_role', () => {
  const page = loadAdmin();
  const cell = makeRow({ listed: ['core'], unlisted: ['retired'] });
  page.pick(cell, 'core');
  assert.deepStrictEqual(cell.posted(), ['core', 'retired'],
    'a save must not quietly drop a role that is no longer defined');
});

test('portctlChange__picking_off__drops_every_label', () => {
  const page = loadAdmin();
  const cell = makeRow({ listed: ['core', 'edge'], held: ['core', 'edge'], unlisted: ['retired'] });
  page.pick(cell, '');
  assert.strictEqual(cell.select.value, '');
  assert.deepStrictEqual(cell.posted(), []);
  cell.chips.forEach((chip) => assert.strictEqual(chip.hidden, true));
  assert.strictEqual(cell.option('core').disabled, false, 'roles can be picked again');
});

test('portctlChange__picking_any_port__drops_every_label', () => {
  const page = loadAdmin();
  const cell = makeRow({ listed: ['core'], held: ['core'], unlisted: ['retired'] });
  page.pick(cell, '_global_');
  assert.strictEqual(cell.select.value, '_global_');
  assert.deepStrictEqual(cell.posted(), [], 'any port is posted with no roles');
});

test('portctlRemove__the_last_label__falls_back_to_off_never_any_port', () => {
  const page = loadAdmin();
  const cell = makeRow({ listed: ['core'], held: ['core'] });
  page.remove(cell, 'core');
  assert.strictEqual(cell.select.value, '', 'Off, not "Enabled (any port)"');
  assert.deepStrictEqual(cell.posted(), []);
  assert.strictEqual(cell.chip('core').hidden, true);
  assert.strictEqual(cell.option('core').disabled, false);
});

test('portctlRemove__the_last_undefined_label__falls_back_to_off', () => {
  const page = loadAdmin();
  const cell = makeRow({ unlisted: ['retired'] });
  page.remove(cell, 'retired');
  assert.strictEqual(cell.select.value, '');
  assert.deepStrictEqual(cell.posted(), []);
});

test('portctlRemove__one_of_two__keeps_by_role', () => {
  const page = loadAdmin();
  const cell = makeRow({ listed: ['core', 'edge'], held: ['core', 'edge'] });
  page.remove(cell, 'core');
  assert.strictEqual(cell.select.value, '_roles_');
  assert.deepStrictEqual(cell.posted(), ['edge']);
  assert.strictEqual(cell.option('core').disabled, false, 'the removed role can be picked again');
  assert.strictEqual(cell.option('edge').disabled, true);
});

test('portctlChange__a_role_name_with_quotes__is_matched_by_index', () => {
  const page = loadAdmin();
  const odd = 'x"] option[value="y';
  const cell = makeRow({ listed: [odd, 'edge'] });
  page.pick(cell, odd);
  assert.deepStrictEqual(cell.posted(), [odd]);
  assert.strictEqual(cell.option(odd).disabled, true);
});

test('portctlListeners__other_targets__leave_the_cell_alone', () => {
  const page = loadAdmin();
  const cell = makeRow({ listed: ['core'], held: ['core'] });
  // a click on the label's text rather than its remove button, a click on a
  // text node (not an Element), and a change on an unrelated field
  const label = cell.chip('core');
  assert.doesNotThrow(() => {
    page.dispatch('click', label);
    page.dispatch('click', { nodeType: 3 });
    page.dispatch('change', Object.assign(new FakeElement(['other']), { parent: cell.row }));
  });
  assert.strictEqual(cell.select.value, '_roles_');
  assert.deepStrictEqual(cell.posted(), ['core']);
});
