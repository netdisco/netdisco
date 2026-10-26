// Guards netdisco-ports.js, which draws the Ports tab's table from JSON.
//
// The cells must stay the ones ports.tt drew, which port control, netdisco.js
// and the CSS rely on, so the first test draws the eight fixture ports
// (xt/ports-fixture.json) and compares each cell with the template's output for
// the same port, kept in xt/ports-reference-rows.html. That file is frozen:
// change it only with a deliberate change of the markup.
//
// There is no jsdom in CI, so the page and the DataTables API are faked as far
// as the code touches them.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const source = fs.readFileSync(path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco-ports.js'), 'utf8');
const fixture = JSON.parse(fs.readFileSync(path.join(ROOT, 'xt', 'ports-fixture.json'), 'utf8'));
const reference = fs.readFileSync(path.join(ROOT, 'xt', 'ports-reference-rows.html'), 'utf8');

// the vendored escaper: escapes < > & " and leaves an apostrophe alone
const escapeHtml = (v) =>
  typeof v === 'string' ? v.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;') : v;

const URLS = {
  device_ports: '', search_node: '', search: '', portlog: '', topology: '',
  portssid: '', nodevendor: '', netbios: '', port_nodes: '/nodes'
};

function clone(o) {
  return JSON.parse(JSON.stringify(o));
}

// --- a page just real enough for the loader ---------------------------------

function element(tag) {
  const listeners = {};
  const classes = new Set();
  const e = {
    tagName: tag,
    children: [],
    attrs: {},
    dataset: {},
    isConnected: true,
    listeners,
    classList: {
      add: (...c) => c.forEach((x) => classes.add(x)),
      remove: (...c) => c.forEach((x) => classes.delete(x)),
      contains: (c) => classes.has(c),
      toggle: (c) => (classes.has(c) ? classes.delete(c) : classes.add(c)),
      list: classes
    },
    appendChild(c) { e.children.push(c); return c; },
    setAttribute(k, v) { e.attrs[k] = v; },
    getAttribute(k) { return k in e.attrs ? e.attrs[k] : null; },
    addEventListener(type, fn, capture) { (listeners[type] = listeners[type] || []).push({ fn, capture: Boolean(capture) }); },
    replaceWith(n) { e.replacedWith = n; e.isConnected = false; },
    innerHTML: '',
    ownerDocument: null
  };
  let text = '';
  Object.defineProperty(e, 'textContent', {
    get: () => text,
    set: (v) => { text = v; if (v === '') e.children = []; }
  });
  Object.defineProperty(e, 'className', {
    get: () => Array.from(classes).join(' '),
    set: (v) => { classes.clear(); String(v).split(' ').filter(Boolean).forEach((c) => classes.add(c)); }
  });
  return e;
}

function frame() {
  const doc = { createElement: element };
  const table = element('table');
  table.ownerDocument = doc;
  table.dataset.ndSource = '/ajax/data/device/ports?q=10.0.0.1';
  table.dataset.ndUrls = JSON.stringify(URLS);
  return table;
}

// Loads netdisco-ports.js with the globals it touches stubbed. getJSON is
// called with each url in turn and answers from `answer`.
function load({ answer } = {}) {
  const requests = [];
  const DataTable = { util: { escapeHtml, stripHtml: (h) => String(h).replace(/<[^>]*>/g, '') } };
  const window = {
    ndRequest: {
      getJSON(url) {
        requests.push(url);
        const a = typeof answer === 'function' ? answer(url) : answer;
        return a instanceof Error ? Promise.reject(a) : Promise.resolve(a);
      }
    }
  };
  const built = [];
  const ndTables = { loaders: {} };
  const ndPorts = new Function('DataTable', 'document', 'window', 'ndTables', source + '\nreturn ndPorts;')(
    DataTable, {}, window, ndTables
  );
  const helpers = { build: (table, root, overrides) => { built.push(overrides); table.tBodies = [element('tbody')]; } };
  return { ndPorts, ndTables, requests, built, helpers, window };
}

const settle = () => new Promise((resolve) => setImmediate(resolve));

// A fake DataTables API over rows: enough for toggleGroup, the fold filter and
// the nodes list, which are the parts of it the table's callbacks call.
function fakeApi(rows) {
  const nodes = new Map();
  const api = {
    draws: 0,
    fixed: {},
    nodes,
    rows: () => ({
      every(fn) {
        rows.forEach((row) => fn.call({ data: () => row, node: () => nodes.get(row) || null }));
      }
    }),
    row: (tr) => ({ data: () => tr.row }),
    search: { fixed: (name, fn) => { api.fixed[name] = fn; } },
    draw: () => { api.draws += 1; }
  };
  return api;
}

// --- comparing cells with the template's -------------------------------------

// Markup compared as the browser would read it rather than as written: the
// whitespace Template Toolkit leaves around tags is not content, attribute
// order is not content, and neither is the order of classes. DataTables' own
// data-order, data-filter and data-search are not attributes of the cell
// either, being what render() answers for sort and filter.
function normalize(html) {
  const attrs = (raw) => {
    const out = [];
    raw.replace(/([a-zA-Z_:][-\w:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'))?/g, (m, name, dq, sq) => {
      if (['data-order', 'data-filter', 'data-search'].includes(name)) return m;
      let v = dq !== undefined ? dq : sq !== undefined ? sq : '';
      // a bare & in an attribute is what the template wrote; it reads the same
      v = v.replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim();
      if (name === 'class') v = v.split(' ').filter(Boolean).sort().join(' ');
      out.push(name + '="' + v + '"');
      return m;
    });
    return out.sort().join(' ');
  };
  return html
    .replace(/\s+/g, ' ')
    .replace(/<(\/?)([a-zA-Z][a-zA-Z0-9]*)((?:\s[^<>]*?)?)\s*(\/?)>/g, (m, close, tag, raw, self) => {
      const a = attrs(raw);
      return '<' + close + tag.toLowerCase() + (a ? ' ' + a : '') + (self ? '/' : '') + '>';
    })
    .replace(/\s*(<[^>]+>)\s*/g, '$1')
    .trim();
}

// The deferred nodes box is the one place the markup is meant to differ: the
// template's carried an htmx request, this one is filled by loadNodes.
function maskDeferred(html) {
  return html
    .replace(/<div class="nd_collapsing nd_collapse-pre-hidden nd_nodes-deferred"[\s\S]*?<\/div>/g, '<div DEFERRED></div>')
    .replace(/<div class="nd_collapsing nd_collapse-pre-hidden nd_nodes-fetch">[\s\S]*?<\/div>/g, '<div DEFERRED></div>');
}

function referenceCells() {
  const rows = [];
  const body = reference.slice(reference.indexOf('<tbody>'));
  body.replace(/<tr\b[^>]*>([\s\S]*?)<\/tr>/g, (m, inner) => {
    const cells = [];
    inner.replace(/<td\b([^>]*)>([\s\S]*?)<\/td>/g, (mm, attrs, html) => { cells.push({ attrs, html }); return mm; });
    rows.push(cells);
    return m;
  });
  return rows;
}

function drawnCell(ndPorts, name, row, ctx) {
  const column = ndPorts.columnFor(name, ctx);
  const a = column.attrs ? column.attrs(row, ctx) : {};
  const attrs = Object.keys(a).map((k) => k + '="' + escapeHtml(String(a[k])) + '"').join(' ');
  return { attrs, html: column.html(row, ctx) };
}

test('cells__the_fixture_ports__are_the_cells_ports_tt_drew', () => {
  const { ndPorts } = load();
  const ctx = { urls: URLS, meta: fixture.meta };
  const expected = referenceCells();
  assert.strictEqual(expected.length, fixture.rows.length, 'the reference holds one row per fixture port');
  const names = ['status'].concat(fixture.columns.map((c) => c.name));
  fixture.rows.forEach((row, i) => {
    assert.strictEqual(expected[i].length, names.length, row.port + ': the template drew as many cells as there are columns');
    names.forEach((name, j) => {
      const got = drawnCell(ndPorts, name, clone(row), ctx);
      const want = expected[i][j];
      assert.strictEqual(
        normalize(maskDeferred('<td ' + got.attrs + '>' + got.html + '</td>')),
        normalize(maskDeferred('<td ' + want.attrs + '>' + want.html + '</td>')),
        row.port + ' / ' + name
      );
    });
  });
});

test('cells__every_value_from_the_server__is_escaped', () => {
  const { ndPorts } = load();
  const hostile = '<img src=x onerror=alert(1)>"';
  const ctx = { urls: URLS, meta: clone(fixture.meta) };
  ctx.meta.params.p_vlan_names = 1;
  const row = {
    port: hostile, descr: hostile, name: hostile, type: hostile, mac: hostile, speed: hostile, stp: hostile,
    up_admin: 'up', up: 'up', slave_of: hostile, vlan: hostile, native_vlan_name: hostile,
    error_disable_cause: hostile, comment: hostile, tags: [hostile], ssids: [hostile],
    remote_ip: hostile, remote_dns: hostile, remote_port: hostile, remote_id: hostile, remote_type: hostile,
    neighbor_ip: hostile, neighbor_dns: hostile, neighbor_mac: hostile, remote_inventory: hostile,
    nac: { port_status: hostile, state: hostile, user: hostile }, node_count: 1,
    nodes: [{ mac: hostile, vlan: '5', ips: [{ ip: hostile, dns: hostile }], ssids: [hostile], vendor: hostile,
      age: hostile, netbios: [{ domain: hostile, nbname: hostile, nbuser: hostile, ip: hostile }] }],
    vlan_count: 1, vlans: [hostile], power: { admin: 'true', status: hostile }
  };
  ctx.meta.params = Object.assign({}, ctx.meta.params, {
    c_admin: 0, c_descr: 1, c_comment: 1, c_type: 1, c_mac: 1, c_speed: 1, c_stp: 1, c_error: 1, c_nac_summary: 1,
    n_ssid: 1, n_vendor: 1, n_age: 1, n_netbios: 1, n_dns: 1, n_inventory: 1, n_detailed_inventory: 1
  });
  ['status', 'c_port', 'c_descr', 'c_comment', 'c_type', 'c_name', 'c_tags', 'c_speed', 'c_error', 'c_mac', 'c_pvid',
    'c_vmember', 'c_power', 'c_ssid', 'c_nac_summary', 'c_neighbors', 'c_stp'].forEach((name) => {
    const html = ndPorts.columnFor(name, ctx).html(clone(row), ctx);
    assert.ok(!html.includes('<img'), name + ' places a server value as markup: ' + html);
  });
  const nodes = ndPorts.nodesHtml(row, row.nodes, ctx);
  assert.ok(!nodes.includes('<img'), 'a node places a server value as markup');
  assert.ok(nodes.includes('&lt;img src=x onerror=alert(1)&gt;&quot;'), 'and escapes it, quotes included');
});

// Moved from xt/85-postfix-conditional-escaping.t, which checked the same
// three cases against ports.tt while Template Toolkit drew them.
test('neighbors__detailed_inventory__escapes_what_the_server_sent_and_prints_nothing_it_did_not', () => {
  const { ndPorts } = load();
  const ctx = { urls: URLS, meta: clone(fixture.meta) };
  ctx.meta.params.n_detailed_inventory = 1;
  const column = ndPorts.columnFor('c_neighbors', ctx);

  const discovered = column.html({
    port: 'Gi1/1', remote_ip: '<b>85a-ip</b>', remote_id: '<b>85a-id</b>', remote_type: '<b>85a-type</b>',
    neighbor_ip: '198.51.100.9', neighbor_dns: 'switch.example.com', manual_topo: 1
  }, ctx);
  ['85a-ip', '85a-id', '85a-type'].forEach((v) => {
    assert.ok(discovered.includes('&lt;b&gt;' + v + '&lt;/b&gt;'), v + ' is escaped');
    assert.ok(!discovered.includes('<b>' + v + '</b>'), v + ' is not placed as markup');
  });
  assert.ok(discovered.includes('class="fas fa-link text-warning"'), 'the class literal beside them is still markup');

  const undiscovered = column.html({
    port: 'Gi1/1', remote_ip: 'plain-85b-ip', remote_id: '<b>85b-id</b>', remote_type: '<b>85b-type</b>'
  }, ctx);
  ['85b-id', '85b-type'].forEach((v) => {
    assert.ok(undiscovered.includes('&lt;b&gt;' + v + '&lt;/b&gt;'), v + ' is escaped');
    assert.ok(!undiscovered.includes('<b>' + v + '</b>'), v + ' is not placed as markup');
  });

  const bare = column.html({ port: 'Gi1/1', remote_ip: 'plain-85c-ip' }, ctx);
  assert.ok(!bare.includes('id: '), 'with no id or type there is no inventory line');
});

// --- sorting and filtering ---------------------------------------------------

test('columns__the_status_column__neither_sorts_nor_filters', () => {
  const { ndPorts } = load();
  const col = ndPorts.dataTableColumn('status', { urls: URLS, meta: fixture.meta }, true);
  assert.strictEqual(col.orderable, false);
  assert.strictEqual(col.searchable, false);
});

test('columns__the_name_columns__sort_with_portsort_and_the_numeric_ones_as_numbers', () => {
  const { ndPorts } = load();
  const ctx = { urls: URLS, meta: fixture.meta };
  ['c_port', 'c_descr', 'c_name'].forEach((n) => assert.strictEqual(ndPorts.dataTableColumn(n, ctx).type, 'portsort', n));
  ['c_ifindex', 'c_mtu', 'c_pvid'].forEach((n) => assert.strictEqual(ndPorts.dataTableColumn(n, ctx).type, 'num', n));
  assert.strictEqual(ndPorts.dataTableColumn('c_descr', ctx).type, 'portsort');
  assert.strictEqual(ndPorts.dataTableColumn('c_type', ctx).type, 'string');
});

test('columns__render__answers_display_with_markup_and_sort_and_filter_with_text', () => {
  const { ndPorts } = load();
  const ctx = { urls: URLS, meta: fixture.meta };
  const row = clone(fixture.rows[0]);
  const port = ndPorts.dataTableColumn('c_port', ctx).render;
  assert.ok(port(null, 'display', row).includes('<a'));
  assert.strictEqual(port(null, 'sort', row), 'Gi1/1');
  assert.strictEqual(port(null, 'filter', row), 'Gi1/1');
  const vmember = ndPorts.dataTableColumn('c_vmember', ctx).render;
  const sorted = vmember(null, 'sort', clone(fixture.rows[6]));
  assert.ok(sorted.includes('3 VLANs') && sorted.includes('10, 20'), 'a column with no value of its own sorts on its text: ' + sorted);
});

test('columns__the_nodes_column__filters_on_the_search_text_under_c_nodes_and_on_its_text_without', () => {
  const { ndPorts } = load();
  const row = clone(fixture.rows[0]);
  const withNodes = { urls: URLS, meta: fixture.meta };
  assert.strictEqual(ndPorts.dataTableColumn('c_neighbors', withNodes).render(null, 'filter', row), row.search);
  const bare = clone(fixture.meta);
  bare.params.c_nodes = 0;
  const neighbor = Object.assign(clone(row), { remote_ip: '192.0.2.1', remote_dns: 'sw2.example.com' });
  const text = ndPorts.dataTableColumn('c_neighbors', { urls: URLS, meta: bare }).render(null, 'filter', neighbor);
  assert.ok(text.includes('sw2.example.com') && text !== row.search, 'the cell\'s own text: ' + text);
});

test('columns__a_cell_drawn_once__is_not_worked_out_again_to_sort_and_filter', () => {
  const { ndPorts } = load();
  const ctx = { urls: URLS, meta: fixture.meta };
  const col = ndPorts.dataTableColumn('c_tags', ctx);
  const row = { port: 'Gi1/1', tags: ['a', 'b'] };
  assert.strictEqual(col.render(null, 'sort', row), 'a b');
  assert.strictEqual(col.render(null, 'filter', row), 'a b');
});

test('columns__createdCell__sets_the_attributes_port_control_reads', () => {
  const { ndPorts } = load();
  const ctx = { urls: URLS, meta: fixture.meta };
  const td = element('td');
  ndPorts.dataTableColumn('c_name', ctx).createdCell(td, null, clone(fixture.rows[0]));
  assert.strictEqual(td.attrs['data-field'], 'c_name');
  assert.strictEqual(td.attrs['data-for-port'], 'Gi1/1');
  assert.strictEqual(td.attrs.contenteditable, 'true');
  assert.ok(td.classList.contains('nd_editable-cell'));
  const plain = element('td');
  ndPorts.dataTableColumn('c_name', ctx).createdCell(plain, null, { port: 'Gi1/2' });
  assert.ok(plain.classList.contains('nd_editable-cell'), 'a name that cannot be edited still has the class');
  assert.strictEqual(plain.attrs.contenteditable, undefined);
});

// --- plugin and custom field columns ----------------------------------------

function extraContext(extra, params) {
  const meta = clone(fixture.meta);
  meta.extra = extra;
  Object.assign(meta.params, params || {});
  return { urls: URLS, meta };
}

test('extra__a_cell_the_server_drew__is_placed_as_it_is', () => {
  const { ndPorts } = load();
  const ctx = extraContext({ c_x: { field: 'cf_x', editable: 0 } });
  const col = ndPorts.columnFor('c_x', ctx);
  const row = { port: 'Gi1/1', cells: { c_x: '<b>drawn</b>' }, fields: { cf_x: 'raw' } };
  assert.strictEqual(col.html(row, ctx), '<b>drawn</b>');
  assert.deepStrictEqual(col.attrs(row, ctx), {});
});

test('extra__a_column_with_no_template__draws_its_field_editable_where_port_control_allows', () => {
  const { ndPorts } = load();
  const ctx = extraContext({ c_x: { field: 'cf_x', editable: 1 } }, { c_admin: 1 });
  const col = ndPorts.columnFor('c_x', ctx);
  const row = { port: 'Gi1/1', fields: { cf_x: '<raw>' }, acl_name: 1 };
  assert.ok(col.html(row, ctx).includes('nd_edit-icon'));
  assert.ok(col.html(row, ctx).includes('&lt;raw&gt;'));
  assert.strictEqual(col.attrs(row, ctx)['data-field'], 'cf_x');
  const locked = { port: 'Gi1/2', fields: { cf_x: 'v' } };
  assert.ok(!col.html(locked, ctx).includes('nd_edit-icon'));
  assert.strictEqual(col.attrs(locked, ctx)['data-field'], undefined);
  assert.strictEqual(col.attrs(locked, ctx).class, 'nd_editable-cell');
});

test('extra__a_cell_the_columns_acl_hides__is_drawn_empty', () => {
  const { ndPorts } = load();
  const ctx = extraContext({ c_x: { field: 'cf_x', editable: 1 } }, { c_admin: 1 });
  const col = ndPorts.columnFor('c_x', ctx);
  const row = { port: 'Gi1/1', hidden_cells: { c_x: 1 }, fields: { cf_x: 'secret' }, acl_name: 1 };
  assert.strictEqual(col.html(row, ctx), '');
  assert.deepStrictEqual(col.attrs(row, ctx), {});
  assert.strictEqual(col.value(row, ctx), '');
});

test('extra__a_registered_renderer__draws_the_column_from_the_rows_data', () => {
  const { ndPorts } = load();
  ndPorts.registerColumn('demo', {
    html: (r, c) => '<i>' + ndPorts.esc(r.data.c_x.label) + '</i>',
    value: (r) => r.data.c_x.rank,
    attrs: (r) => ({ 'data-demo': r.port })
  });
  const ctx = extraContext({ c_x: { field: 'cf_x', editable: 0, renderer: 'demo' } });
  const col = ndPorts.columnFor('c_x', ctx);
  const row = { port: 'Gi1/1', data: { c_x: { label: '<a>', rank: 7 } } };
  assert.strictEqual(col.html(row, ctx), '<i>&lt;a&gt;</i>');
  assert.strictEqual(col.value(row, ctx), 7);
  assert.deepStrictEqual(col.attrs(row, ctx), { 'data-demo': 'Gi1/1' });
  const hidden = { port: 'Gi1/1', hidden_cells: { c_x: 1 }, data: { c_x: { label: 'x' } } };
  assert.strictEqual(col.html(hidden, ctx), '', 'the ACL applies to a renderer too');
});

test('extra__a_renderer_named_but_never_registered__falls_back_to_the_field', () => {
  const { ndPorts } = load();
  const ctx = extraContext({ c_x: { field: 'cf_x', editable: 0, renderer: 'missing' } });
  const row = { port: 'Gi1/1', fields: { cf_x: 'v' } };
  assert.ok(ndPorts.columnFor('c_x', ctx).html(row, ctx).includes('>v<'));
});

test('columns__a_name_that_is_neither_built_in_nor_an_extra__is_an_error', () => {
  const { ndPorts } = load();
  assert.throws(() => ndPorts.columnFor('c_nope', { urls: URLS, meta: fixture.meta }), /no column named "c_nope"/);
  assert.throws(() => ndPorts.columnFor('c_x', extraContext({})), /no column named "c_x"/,
    'a plugin column the route did not list in meta.extra is not guessed at');
});

// --- the loader --------------------------------------------------------------

test('loader__registers_itself_as_the_ports_loader', () => {
  const { ndTables, ndPorts } = load();
  assert.strictEqual(ndTables.loaders.ports, ndPorts.load);
});

test('loader__fetches_the_source_and_builds_the_table_from_the_columns_and_rows', async () => {
  const { ndTables, requests, built, helpers } = load({ answer: clone(fixture) });
  const table = frame();
  await ndTables.loaders.ports(table, null, helpers);
  assert.deepStrictEqual(requests, ['/ajax/data/device/ports?q=10.0.0.1']);
  assert.strictEqual(built.length, 1);
  const o = built[0];
  assert.strictEqual(o.deferRender, true);
  assert.strictEqual(o.data.length, fixture.rows.length);
  assert.strictEqual(o.columns.length, 1 + fixture.columns.length, 'the status column and one per column');
  assert.deepStrictEqual(o.order, [[1, 'asc']]);
  const [thead] = table.children;
  assert.strictEqual(thead.tagName, 'thead');
  const labels = thead.children[0].children.map((th) => th.textContent);
  assert.deepStrictEqual(labels, [''].concat(fixture.columns.map((c) => c.label)));
  assert.strictEqual(table.dataset.ndLoaded, '1');
});

test('loader__a_table_with_only_the_status_column__is_not_ordered_on_a_column_that_is_not_there', async () => {
  const payload = clone(fixture);
  payload.columns = [];
  const { ndTables, built, helpers } = load({ answer: payload });
  await ndTables.loaders.ports(frame(), null, helpers);
  assert.deepStrictEqual(built[0].order, []);
});

test('loader__no_rows__says_so_in_place_of_the_table', async () => {
  const { ndTables, built, helpers } = load({ answer: { columns: [], rows: [], meta: {} } });
  const table = frame();
  await ndTables.loaders.ports(table, null, helpers);
  assert.strictEqual(built.length, 0);
  assert.strictEqual(table.replacedWith.textContent, 'No matching records.');
  assert.ok(table.replacedWith.classList.contains('alert-info'));
});

test('loader__an_answer_for_a_pane_that_has_been_replaced__is_dropped', async () => {
  const { ndTables, built, helpers } = load({ answer: clone(fixture) });
  const table = frame();
  table.isConnected = false;
  await ndTables.loaders.ports(table, null, helpers);
  assert.strictEqual(built.length, 0);
  assert.strictEqual(table.children.length, 0, 'and nothing is drawn into it');
});

test('loader__a_failed_request__shows_a_retry_that_asks_again', async () => {
  let fail = true;
  const { ndTables, requests, built, helpers } = load({ answer: () => (fail ? new Error('down') : clone(fixture)) });
  const table = frame();
  const originalError = console.error;
  console.error = () => {};
  try {
    await ndTables.loaders.ports(table, null, helpers);
  } finally {
    console.error = originalError;
  }
  assert.strictEqual(built.length, 0);
  const cell = table.children[0].children[0].children[0];
  assert.ok(cell.innerHTML.includes('Could not load the ports'));
  assert.ok(cell.innerHTML.includes('nd_ports-retry'));

  fail = false;
  const click = table.listeners.click[0].fn;
  let prevented = false;
  click({ target: { closest: (sel) => (sel === '.nd_ports-retry' ? {} : null) }, preventDefault: () => { prevented = true; } });
  await settle();
  assert.ok(prevented);
  assert.strictEqual(requests.length, 2, 'the retry asks again');
  assert.strictEqual(built.length, 1, 'and draws the table when it is answered');
  assert.strictEqual(table.listeners.click.length, 1, 'without binding the retry twice');
});

test('loader__a_column_the_script_does_not_know__shows_the_failure_and_draws_nothing', async () => {
  const payload = clone(fixture);
  payload.columns.push({ name: 'c_nope', label: 'Nope' });
  const { ndTables, built, helpers } = load({ answer: payload });
  const table = frame();
  const originalError = console.error;
  console.error = () => {};
  try {
    await ndTables.loaders.ports(table, null, helpers);
  } finally {
    console.error = originalError;
  }
  assert.strictEqual(built.length, 0);
  assert.ok(table.children[0].children[0].children[0].innerHTML.includes('Could not load the ports'));
});

test('loader__a_click_elsewhere_in_the_frame__is_not_a_retry', async () => {
  const { ndTables, requests, helpers } = load({ answer: clone(fixture) });
  const table = frame();
  await ndTables.loaders.ports(table, null, helpers);
  table.listeners.click[0].fn({ target: { closest: () => null }, preventDefault: () => assert.fail('prevented') });
  assert.strictEqual(requests.length, 1);
});

// --- folding subinterfaces ---------------------------------------------------

function foldable(params) {
  const payload = clone(fixture);
  Object.assign(payload.meta.params, { p_fold_dotzero: 0, p_fold_subinterfaces: 0 }, params);
  payload.rows = [
    { port: 'Gi1/1', up_admin: 'up', up: 'up', has_group: 1, only_dot_zero: 1 },
    { port: 'Gi1/1.0', up_admin: 'up', up: 'up', group: 'Gi1/1', is_dot_zero: 1 },
    { port: 'Gi1/1.1', up_admin: 'up', up: 'up', group: 'Gi1/1' },
    { port: 'Gi1/2', up_admin: 'up', up: 'up' }
  ];
  return payload;
}

test('folding__startsFolded__follows_the_two_options', () => {
  const { ndPorts } = load();
  const dot = { group: 'g', is_dot_zero: 1 };
  const sub = { group: 'g' };
  assert.strictEqual(ndPorts.startsFolded(dot, { p_fold_dotzero: 1 }), true);
  assert.strictEqual(ndPorts.startsFolded(sub, { p_fold_dotzero: 1 }), false);
  assert.strictEqual(ndPorts.startsFolded(sub, { p_fold_subinterfaces: 1 }), true);
  assert.strictEqual(ndPorts.startsFolded({}, { p_fold_subinterfaces: 1 }), false, 'a port outside any group never folds');
  assert.strictEqual(ndPorts.startsFolded(dot, {}), false);
});

test('folding__a_row_of_a_group__is_marked_as_the_old_markup_marked_it', async () => {
  const payload = foldable({ p_fold_dotzero: 1 });
  const { ndTables, built, helpers } = load({ answer: payload });
  await ndTables.loaders.ports(frame(), null, helpers);
  const createdRow = built[0].createdRow;
  const rows = built[0].data;

  const tr = element('tr');
  createdRow(tr, rows[1]);
  assert.ok(tr.classList.contains('nd_collapsible'));
  assert.strictEqual(tr.attrs['data-collapsed-group'], 'Gi1/1');
  assert.strictEqual(tr.attrs['data-is-collapsed'], 'true', 'the .0 row starts folded under p_fold_dotzero');

  const other = element('tr');
  createdRow(other, rows[2]);
  assert.strictEqual(other.attrs['data-is-collapsed'], 'false');

  const plain = element('tr');
  createdRow(plain, rows[3]);
  assert.deepStrictEqual(plain.attrs, {}, 'a port outside any group is left alone');
});

test('folding__the_tables_own_filter__hides_the_folded_rows_and_nothing_else', async () => {
  const payload = foldable({ p_fold_subinterfaces: 1 });
  const { ndTables, built, helpers } = load({ answer: payload });
  await ndTables.loaders.ports(frame(), null, helpers);
  const api = fakeApi(built[0].data);
  built[0].initComplete.call({ api: () => api });
  const keep = api.fixed.nd_fold;
  assert.deepStrictEqual(built[0].data.map((r) => keep('', r)), [true, false, false, true]);
  assert.ok(api.draws >= 1, 'and the table is drawn again with it');
});

test('folding__a_click_on_the_toggle__flips_the_groups_rows_and_the_icon', async () => {
  const payload = foldable({ p_fold_dotzero: 1 });
  const { ndTables, built, helpers } = load({ answer: payload });
  const table = frame();
  await ndTables.loaders.ports(table, null, helpers);
  const rows = built[0].data;
  const api = fakeApi(rows);
  // a row already drawn has its tr; the others only change in their data
  const tr = element('tr');
  api.nodes.set(rows[1], tr);
  built[0].initComplete.call({ api: () => api });
  const draws = api.draws;

  const icon = element('i');
  icon.classList.add('fa-list-ol');
  const toggle = { getAttribute: () => 'Gi1/1', querySelector: () => icon };
  const bubble = table.tBodies[0].listeners.click.find((l) => !l.capture).fn;
  bubble({ target: { closest: (sel) => (sel === '.nd_row-collapser-toggle' ? toggle : null) } });

  assert.strictEqual(rows[1]._folded, false, 'the folded row is shown');
  assert.strictEqual(rows[2]._folded, true, 'and the shown one folded');
  assert.strictEqual(rows[3]._folded, undefined, 'a port of another group is untouched');
  assert.strictEqual(tr.attrs['data-is-collapsed'], 'false', 'a row on screen follows at once');
  assert.ok(!icon.classList.contains('fa-list-ol'));
  assert.ok(icon.classList.contains('fa-arrow-up-wide-short') && icon.classList.contains('fa-rotate-180'));
  assert.strictEqual(api.draws, draws + 1);
});

// --- the nodes of a port over the threshold ----------------------------------

function opener(box, row) {
  const tr = element('tr');
  tr.row = row;
  box.closest = (sel) => (sel === 'tr' ? tr : null);
  const total = { nextElementSibling: box };
  return { closest: (sel) => (sel === '.nd_nodes-total' ? total : null) };
}

async function opened(answer) {
  const payload = clone(fixture);
  payload.meta.node_params = '&n_ip4=1';
  payload.meta.device = '10.0.0.1';
  const harness = load({ answer: (url) => (url.startsWith('/nodes') ? answer : payload) });
  const table = frame();
  await harness.ndTables.loaders.ports(table, null, harness.helpers);
  const api = fakeApi(harness.built[0].data);
  harness.built[0].initComplete.call({ api: () => api });
  const box = element('div');
  box.classList.add('nd_nodes-fetch');
  const row = harness.built[0].data[0];
  const target = opener(box, row);
  const capture = table.tBodies[0].listeners.click.find((l) => l.capture).fn;
  api.row = (tr) => ({ data: () => tr.row });
  return { harness, table, box, row, target, capture };
}

test('nodes__opening_a_box_over_the_threshold__fetches_that_ports_nodes_once', async () => {
  const { harness, box, row, target, capture } = await opened({ nodes: [{ mac: 'aa:bb', ips: [] }] });
  capture({ target: { closest: (sel) => (sel === '.nd_collapse-vlans' ? target : null) } });
  await settle();
  assert.deepStrictEqual(harness.requests.slice(1), ['/nodes?q=10.0.0.1&port=Gi1%2F1&n_ip4=1']);
  assert.ok(box.innerHTML.includes('aa:bb'), 'the nodes are drawn into the box');
  assert.ok(box.classList.contains('nd_loaded'));
  assert.strictEqual(row.nodes.length, 1, 'and kept on the row');

  capture({ target: { closest: (sel) => (sel === '.nd_collapse-vlans' ? target : null) } });
  await settle();
  assert.strictEqual(harness.requests.length, 2, 'opening it again does not ask again');
});

test('nodes__a_box_that_is_not_a_fetch_box__is_left_to_netdisco_js', async () => {
  const { harness, box, target, capture } = await opened({ nodes: [] });
  box.classList = element('div').classList;
  capture({ target: { closest: (sel) => (sel === '.nd_collapse-vlans' ? target : null) } });
  await settle();
  assert.strictEqual(harness.requests.length, 1);
});

test('nodes__a_failed_fetch__offers_a_retry_and_a_reopened_box_tries_again', async () => {
  const failing = await opened(new Error('down'));
  const { harness, box, target, capture } = failing;
  capture({ target: { closest: (sel) => (sel === '.nd_collapse-vlans' ? target : null) } });
  await settle();
  assert.ok(box.innerHTML.includes('nd_nodes-fetch-retry'));
  assert.ok(!box.classList.contains('nd_loaded'));

  capture({ target: { closest: (sel) => (sel === '.nd_collapse-vlans' ? target : null) } });
  await settle();
  assert.strictEqual(harness.requests.length, 3, 'a box that failed fetches again when opened');
});

// --- the frame ---------------------------------------------------------------

test('frame__ports_tt__names_the_loader_and_every_url_the_script_reads', () => {
  const tt = fs.readFileSync(path.join(ROOT, 'share', 'views', 'ajax', 'device', 'ports.tt'), 'utf8');
  assert.ok(/data-nd-loader="ports"/.test(tt), 'the template names the ports loader');
  assert.ok(/data-nd-source="\[% data_source \| html_entity %\]"/.test(tt));
  const start = tt.indexOf("data-nd-urls='");
  const attr = tt.slice(start + "data-nd-urls='".length, tt.indexOf("'>", start));
  const json = JSON.parse(attr.replace(/\[%[^%]*%\]/g, 'x'));
  const read = new Set(Array.from(source.matchAll(/\burls\.([a-z_]+)/g), (m) => m[1]));
  read.forEach((key) => assert.ok(key in json, 'data-nd-urls has "' + key + '", which netdisco-ports.js reads'));
});

test('frame__every_loader_a_template_names__is_registered_by_a_script', () => {
  const found = [];
  (function walk(dir) {
    fs.readdirSync(dir, { withFileTypes: true }).forEach((e) => {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) return walk(full);
      for (const m of fs.readFileSync(full, 'utf8').matchAll(/data-nd-loader="([a-z_]+)"/g)) found.push(m[1]);
    });
  })(path.join(ROOT, 'share', 'views'));
  assert.ok(found.length > 0);
  found.forEach((name) => assert.ok(source.includes('ndTables.loaders.' + name + ' ='), name + ' has a loader'));
});
