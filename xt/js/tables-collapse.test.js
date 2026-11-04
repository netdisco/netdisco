// Guards the folding of subinterface groups in the Ports table
// (ndTables.collapse and the portsCollapse callback in netdisco-tables.js).
//
// It used to draw the whole table with paging switched off to reach every
// row's toggle, at table build and again on every click, which cost more than
// the table's own first draw at 5000 ports. The fold is a search filter on the
// row attribute and one click listener on the table, so none of that is
// needed; these tests hold that shape.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', '..', 'share', 'public', 'javascripts', 'netdisco-tables.js'), 'utf8');

// A row as the fold sees it: the group it belongs to and whether it is folded.
function row(group, collapsed) {
  const attrs = {};
  if (group !== undefined) {
    attrs['data-collapsed-group'] = group;
    attrs['data-is-collapsed'] = collapsed ? 'true' : 'false';
  }
  return {
    dataset: group === undefined ? {} : { collapsedGroup: group },
    getAttribute: (name) => (name in attrs ? attrs[name] : null),
    setAttribute: (name, value) => { attrs[name] = value; },
  };
}

function toggleFor(group) {
  const classes = new Set(['fa-arrow-up-wide-short', 'fa-rotate-180']);
  const icon = { classList: { toggle: (c) => (classes.has(c) ? classes.delete(c) : classes.add(c)) } };
  return {
    classes,
    getAttribute: (name) => (name === 'data-collapsed-group' ? group : null),
    querySelector: () => icon,
  };
}

function table() {
  const listeners = {};
  return {
    dataset: {},
    listeners,
    addEventListener: (type, fn) => { (listeners[type] = listeners[type] || []).push(fn); },
  };
}

// `rows` are all the table's rows, on any page. DataTables 3 names its
// settings table and data[i].tr; names2 switches to the version 2 names.
function load({ rows = [], names2 = false } = {}) {
  const draws = [];
  const DataTable = function (el) {
    return {
      rows: () => ({ nodes: () => ({ each: (fn) => rows.forEach(fn) }) }),
      draw: (arg) => draws.push(arg),
    };
  };
  DataTable.util = { escapeHtml: (v) => v };
  DataTable.ext = { search: [] };
  DataTable.render = {};
  const document = { body: { dataset: {} }, querySelectorAll: () => [], getElementById: () => null };
  const fn = new Function('DataTable', 'document', 'window', source + '\nreturn ndTables;');
  const ndTables = fn(DataTable, document, {});
  const settingsFor = (t) => (names2
    ? { tableId: 'dp-data-table', nTable: t, aoData: rows.map((r) => ({ nTr: r })) }
    : { tableId: 'dp-data-table', table: t, data: rows.map((r) => ({ tr: r })) });
  return { ndTables, DataTable, draws, settingsFor };
}


test('portsCollapse__resolved__installs_the_filter_before_any_draw', () => {
  const t = table();
  const { ndTables, DataTable, draws } = load();
  const initComplete = ndTables.resolveCallback('portsCollapse', {}, t);

  assert.strictEqual(DataTable.ext.search.length, 1,
    'the filter is in place when the callback is resolved, which is before the first draw');
  assert.strictEqual(typeof initComplete, 'function');
  initComplete.call({ api: () => { throw new Error('initComplete must not need the API'); } });
  assert.deepStrictEqual(draws, [], 'and building the table draws it no more than the first time');
});

test('filter__a_folded_row__is_hidden_and_the_rest_stay', () => {
  const t = table();
  const rows = [row('Gi1', true), row('Gi2', false), row(undefined), row('Gi1', true)];
  const { ndTables, DataTable, settingsFor } = load({ rows });
  ndTables.resolveCallback('portsCollapse', {}, t);
  const [filter] = DataTable.ext.search;
  const settings = settingsFor(t);

  assert.deepStrictEqual(rows.map((_, i) => filter(settings, [], i)), [false, true, true, false]);
});

test('filter__another_table__is_left_alone', () => {
  const t = table();
  const rows = [row('Gi1', true)];
  const { ndTables, DataTable, settingsFor } = load({ rows });
  ndTables.resolveCallback('portsCollapse', {}, t);

  assert.strictEqual(DataTable.ext.search[0](settingsFor(table()), [], 0), true,
    'a folded row of some other table is not this filter\'s to hide');
});

test('filter__datatables_2_settings_names__still_work', () => {
  const t = table();
  const rows = [row('Gi1', true), row('Gi2', false)];
  const { ndTables, DataTable, settingsFor } = load({ rows, names2: true });
  ndTables.resolveCallback('portsCollapse', {}, t);
  const settings = settingsFor(t);

  assert.deepStrictEqual([0, 1].map((i) => DataTable.ext.search[0](settings, [], i)), [false, true]);
});

test('filter__a_second_build__replaces_the_first_rather_than_adding_one', () => {
  const { ndTables, DataTable } = load();
  ndTables.resolveCallback('portsCollapse', {}, table());
  ndTables.resolveCallback('portsCollapse', {}, table());

  assert.strictEqual(DataTable.ext.search.length, 1,
    'a pane swapped in again must not leave the old table\'s filter running on every draw');
});

test('click__a_toggle__flips_its_group_on_every_page_and_draws_once_in_place', () => {
  const t = table();
  const rows = [row('Gi1', true), row('Gi2', true), row('Gi1', true), row(undefined)];
  const { ndTables, draws } = load({ rows });
  ndTables.resolveCallback('portsCollapse', {}, t);
  const toggle = toggleFor('Gi1');

  t.listeners.click[0]({ target: { closest: () => toggle } });

  assert.deepStrictEqual(rows.map((r) => r.getAttribute('data-is-collapsed')),
    ['false', 'true', 'false', null], 'both Gi1 rows open, whatever page they are on');
  assert.deepStrictEqual(draws, [false], 'one redraw that keeps the page');
  assert.ok(!toggle.classes.has('fa-arrow-up-wide-short'), 'the icon follows');

  t.listeners.click[0]({ target: { closest: () => toggle } });
  assert.deepStrictEqual(rows.map((r) => r.getAttribute('data-is-collapsed')),
    ['true', 'true', 'true', null], 'a second click folds the group again');
});

test('click__something_that_is_not_a_toggle__does_nothing', () => {
  const t = table();
  const rows = [row('Gi1', true)];
  const { ndTables, draws } = load({ rows });
  ndTables.resolveCallback('portsCollapse', {}, t);

  t.listeners.click[0]({ target: { closest: () => null } });
  t.listeners.click[0]({ target: {} });

  assert.strictEqual(rows[0].getAttribute('data-is-collapsed'), 'true');
  assert.deepStrictEqual(draws, []);
});

test('bind__the_same_table_twice__adds_one_listener', () => {
  const t = table();
  const { ndTables } = load();
  ndTables.collapse.bind(t);
  ndTables.collapse.bind(t);

  assert.strictEqual(t.listeners.click.length, 1);
});

test('source__the_paging_dance__is_gone', () => {
  assert.ok(!/page\.len\(-1\)/.test(source),
    'drawing every row to reach its toggle is what this guards against');
});
