// Guards netdisco-ports.js, which draws the Ports tab's table from JSON.
//
// The cells must stay the ones ports.tt drew, which port control, netdisco.js
// and the CSS rely on, so the first test draws the thirteen fixture ports
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

// A DataTables instance as far as a change of columns reads and ends it
function fakeDataTable(options) {
  const dt = {
    options,
    destroyed: false,
    processed: [],
    state: { order: options.order, len: options.pageLength || 10, page: 0, search: '' },
    order: () => dt.state.order,
    search: () => dt.state.search,
    processing: (on) => dt.processed.push(on),
    destroy: () => { dt.destroyed = true; }
  };
  dt.page = () => dt.state.page;
  dt.page.len = () => dt.state.len;
  return dt;
}

// Loads netdisco-ports.js with the globals it touches stubbed. getJSON is
// called with each url in turn and answers from `answer`; a promise answers
// when it settles. `document` and `win` add to the page and the window.
function load({ answer, document, win } = {}) {
  const requests = [];
  const DataTable = { util: { escapeHtml, stripHtml: (h) => String(h).replace(/<[^>]*>/g, '') } };
  const window = Object.assign({
    ndRequest: {
      getJSON(url) {
        requests.push(url);
        const a = typeof answer === 'function' ? answer(url) : answer;
        return a instanceof Error ? Promise.reject(a) : Promise.resolve(a);
      }
    }
  }, win);
  const built = [];
  const tables = [];
  const ndTables = { loaders: {} };
  const ndPorts = new Function('DataTable', 'document', 'window', 'ndTables', source + '\nreturn ndPorts;')(
    DataTable, document || {}, window, ndTables
  );
  const helpers = {
    build: (table, root, overrides) => {
      built.push(overrides);
      table.tBodies = [element('tbody')];
      const dt = fakeDataTable(overrides);
      tables.push(dt);
      return dt;
    }
  };
  return { ndPorts, ndTables, requests, built, tables, helpers, window };
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

// --- changing the columns in place -----------------------------------------

test('columns_in_place__a_group_unfolded__keeps_its_icon_when_drawn_again', () => {
  const { ndPorts } = load();
  const parent = { port: 'Gi1/1', has_group: 1, only_dot_zero: 1, up_admin: 'up' };
  const rows = [parent, { port: 'Gi1/1.0', group: 'Gi1/1', is_dot_zero: 1, _folded: true }];
  const ctx = { urls: URLS, meta: { device: '', q: '', params: { p_fold_dotzero: 1 }, settings: {} } };
  const icon = (r) => /fa-list-ol/.test(ndPorts.columnFor('c_port', ctx).html(r, ctx)) ? 'folded' : 'shown';
  assert.strictEqual(icon(parent), 'folded');
  const toggle = { getAttribute: () => 'Gi1/1', querySelector: () => null };
  ndPorts.toggleGroup(fakeApi(rows), toggle);
  assert.strictEqual(rows[1]._folded, false);
  assert.strictEqual(icon(parent), 'shown', 'as the toggle left it, not as the options start it');
});



const colNames = (cols) => cols.map((c) => c.name);

test('columns_in_place__pickColumns__chooses_what_the_server_chose_for_the_fixture', () => {
  const { ndPorts } = load();
  assert.deepStrictEqual(ndPorts.pickColumns(fixture.meta.choices, fixture.meta.params), fixture.columns);
});

// the same cases xt/179-ports-json.t puts to _port_columns
test('columns_in_place__pickColumns__folds_c_nodes_into_c_neighbors_as_the_server_does', () => {
  const { ndPorts } = load();
  const pick = (p) => ndPorts.pickColumns(fixture.meta.choices, p);
  assert.deepStrictEqual(pick({ c_port: 1, c_name: 1 }), [
    { name: 'c_port', label: 'Port' }, { name: 'c_name', label: 'Name' }
  ], 'only the columns asked for, in config order');
  assert.deepStrictEqual(pick({ c_nodes: 1 }), [{ name: 'c_nodes', label: 'Connected Nodes' }]);
  assert.deepStrictEqual(pick({ c_neighbors: 1 }), [{ name: 'c_neighbors', label: 'Connected Devices' }]);
  assert.deepStrictEqual(pick({ c_nodes: 1, c_neighbors: 1 }), [
    { name: 'c_neighbors', label: 'Connected Nodes & Devices' }
  ]);
  assert.deepStrictEqual(pick({ c_admin: 1, c_links: 1 }), [], 'neither c_admin nor c_links without links is a choice');
});

test('columns_in_place__partialQuery__asks_for_the_missing_columns_and_keeps_the_filter', () => {
  const { ndPorts } = load();
  const source = '/ajax/data/device/ports?q=10.0.0.1&f=Gi1%2F*&c_port=on&c_name=on&n_ip4=on&p_fold_dotzero=on&plug=on';
  assert.strictEqual(
    ndPorts.partialQuery(source, ['c_admin', 'c_port', 'c_name', 'plug'], ['c_power']),
    '/ajax/data/device/ports?q=10.0.0.1&f=Gi1%2F*&n_ip4=on&p_fold_dotzero=on&c_power=on'
  );
  assert.strictEqual(
    ndPorts.withFlags('/device?c_stale=on&tab=ports', [], ['c_port']),
    '/device?tab=ports&c_port=on',
    'a c_ flag outside the list is taken out too'
  );
  assert.strictEqual(ndPorts.withFlags('/x', [], []), '/x');
});

test('columns_in_place__missingFlags__brings_the_other_of_nodes_and_neighbors_along', () => {
  const { ndPorts } = load();
  const offered = { c_admin: true, c_port: true, c_nodes: true, c_neighbors: true, c_power: true };
  const loaded = { c_port: true, c_neighbors: true };
  assert.deepStrictEqual(ndPorts.missingFlags(['c_port', 'c_neighbors', 'c_nodes'], loaded, offered), ['c_nodes', 'c_neighbors']);
  assert.deepStrictEqual(ndPorts.missingFlags(['c_port', 'c_nodes'], loaded, offered), ['c_nodes'], 'not when it is not ticked');
  assert.deepStrictEqual(ndPorts.missingFlags(['c_port', 'c_neighbors', 'c_power'], loaded, offered), ['c_power'], 'nor when neither is missing');
  assert.deepStrictEqual(ndPorts.missingFlags(['c_links', 'c_admin'], loaded, offered), ['c_admin'], 'only flags that are offered');
});

test('columns_in_place__mergeRows__merges_by_port_one_level_deep_into_the_plugin_hashes', () => {
  const { ndPorts } = load();
  const rows = [
    { port: 'a', descr: 'x', cells: { one: '<b>1</b>' }, _m: { c_port: 'a' }, _folded: true },
    { port: 'b' }
  ];
  const meta = { extra: { one: { editable: 0 } }, vlan_names: { 1: 'one' }, node_params: '&n_ip4=1' };
  const ok = ndPorts.mergeRows(rows, meta, {
    rows: [{ port: 'b', power: { admin: 'true' } }, { port: 'a', descr: 'y', cells: { two: '2' }, fields: { cf_x: 'v' } }],
    meta: { extra: { two: { editable: 1 } }, vlan_names: { 2: 'two' }, node_params: '' }
  });
  assert.strictEqual(ok, true);
  assert.deepStrictEqual(rows, [
    { port: 'a', descr: 'y', cells: { one: '<b>1</b>', two: '2' }, fields: { cf_x: 'v' }, _folded: true },
    { port: 'b', power: { admin: 'true' } }
  ]);
  assert.deepStrictEqual(meta, {
    extra: { one: { editable: 0 }, two: { editable: 1 } },
    vlan_names: { 1: 'one', 2: 'two' },
    node_params: '&n_ip4=1'
  });
});

test('columns_in_place__mergeRows__changes_nothing_when_the_ports_are_not_the_tables', () => {
  const { ndPorts } = load();
  const rows = [{ port: 'a' }, { port: 'b' }];
  assert.strictEqual(ndPorts.mergeRows(rows, {}, { rows: [{ port: 'a', descr: 'y' }] }), false);
  assert.strictEqual(ndPorts.mergeRows(rows, {}, { rows: [{ port: 'a', descr: 'y' }, { port: 'c' }] }), false);
  assert.deepStrictEqual(rows, [{ port: 'a' }, { port: 'b' }]);
});

// The sidebar's Display Columns boxes, ticked as the fixture was asked for,
// the CSV link and the address bar, around a loaded table. `partial` answers
// every request after the first.
async function columnsPage({ partial } = {}) {
  const boxes = ['c_admin'].concat(colNames(fixture.meta.choices)).map((name) => ({
    name, checked: Boolean(fixture.meta.params[name])
  }));
  const csv = element('a');
  csv.setAttribute('href', '/ajax/content/device/ports?q=10.0.0.1&c_port=on');
  const portlog = element('div');
  const byId = { 'nd_csv-download': csv, nd_portlog: portlog };
  const document = {
    querySelectorAll: (sel) => (sel === '#ports_form #nd_columns input[type=checkbox]' ? boxes : []),
    getElementById: (id) => byId[id] || null
  };
  const submits = [];
  const replaced = [];
  const win = {
    htmx: { trigger: (sel, evt) => submits.push(sel + ' ' + evt) },
    location: { pathname: '/device', search: '?tab=ports&q=10.0.0.1&c_port=on', hash: '#x' },
    history: { state: { htmx: true }, replaceState: (state, title, url) => replaced.push([state, url]) }
  };
  let first = true;
  const h = load({
    document,
    win,
    answer: (url) => {
      if (first) { first = false; return clone(fixture); }
      return partial(url);
    }
  });
  const table = frame();
  await h.ndTables.loaders.ports(table, null, h.helpers);
  const tick = (name, on) => { boxes.find((b) => b.name === name).checked = on; };
  return Object.assign(h, { table, boxes, tick, csv, byId, submits, replaced });
}

// the answer for some columns: each port with only what those columns add
const partialAnswer = (add) => () => ({
  columns: [],
  rows: fixture.rows.map((r) => Object.assign({ port: r.port }, add(r))),
  meta: { extra: {}, vlan_names: {}, node_params: '' }
});

test('columns_in_place__a_column_ticked__fetches_that_column_alone_and_draws_it', async () => {
  const page = await columnsPage({ partial: partialAnswer((r) => ({ descr: 'D ' + r.port })) });
  page.tick('c_descr', true);
  await page.ndPorts.applyColumns(page.table);

  assert.deepStrictEqual(page.requests.slice(1), ['/ajax/data/device/ports?q=10.0.0.1&c_descr=on']);
  assert.deepStrictEqual(page.tables[0].processed, [true, false], 'with the indicator while it waits');
  assert.strictEqual(page.tables[0].destroyed, true);
  assert.strictEqual(page.built.length, 2);
  const o = page.built[1];
  assert.strictEqual(o.data, page.built[0].data, 'drawn from the same rows');
  assert.strictEqual(o.data[0].descr, 'D Gi1/1');
  assert.ok(o.data.some((r) => r.power), 'which keep what they held');
  assert.strictEqual(o.columns.length, 2 + fixture.columns.length);
  const labels = page.table.children[0].children[0].children.map((th) => th.textContent);
  assert.deepStrictEqual(labels.slice(0, 4), ['', 'Port', 'Description', 'Name']);
  assert.strictEqual(o.stateLoadCallback(), null, 'the state saved for the old columns is not applied');
});

test('columns_in_place__a_column_unticked_and_ticked_again__asks_the_server_for_nothing', async () => {
  const page = await columnsPage({ partial: () => { throw new Error('no request expected'); } });
  page.tick('c_power', false);
  await page.ndPorts.applyColumns(page.table);
  page.tick('c_power', true);
  await page.ndPorts.applyColumns(page.table);
  assert.strictEqual(page.requests.length, 1);
  assert.strictEqual(page.built.length, 3);
  assert.strictEqual(page.built[1].columns.length, fixture.columns.length, 'without PoE');
  assert.strictEqual(page.built[2].columns.length, 1 + fixture.columns.length, 'and with it again');
  assert.deepStrictEqual(page.submits, []);
});

test('columns_in_place__the_order_page_and_filter__are_kept_by_column_name', async () => {
  const page = await columnsPage();
  // status c_port c_name c_tags ...: ordered on the tags, descending
  Object.assign(page.tables[0].state, { order: [[3, 'desc']], len: 25, page: 2, search: 'Gi1' });
  page.tick('c_name', false);
  await page.ndPorts.applyColumns(page.table);
  const o = page.built[1];
  assert.deepStrictEqual(o.order, [[2, 'desc']]);
  assert.strictEqual(o.pageLength, 25);
  assert.strictEqual(o.displayStart, 50);
  assert.deepStrictEqual(o.search, { search: 'Gi1' });

  // the column ordered on is gone: back to the first one
  page.tables[1].state.order = [[2, 'desc']];
  page.tick('c_tags', false);
  await page.ndPorts.applyColumns(page.table);
  assert.deepStrictEqual(page.built[2].order, [[1, 'asc']]);
});

test('columns_in_place__nodes_and_neighbors__switch_label_and_keep_their_order', async () => {
  const page = await columnsPage();
  const last = fixture.columns.length; // c_neighbors, the shared cell
  page.tables[0].state.order = [[last, 'asc']];
  page.tick('c_neighbors', false);
  await page.ndPorts.applyColumns(page.table);
  const labels = page.table.children[0].children[0].children.map((th) => th.textContent);
  assert.strictEqual(labels[labels.length - 1], 'Connected Nodes');
  assert.deepStrictEqual(page.built[1].order, [[last, 'asc']], 'the same cell under its other name');
  assert.strictEqual(page.requests.length, 1);
});

test('columns_in_place__the_source_csv_link_and_address_bar__carry_the_columns_shown', async () => {
  const page = await columnsPage({ partial: partialAnswer(() => ({})) });
  page.tick('c_descr', true);
  page.tick('c_admin', false);
  await page.ndPorts.applyColumns(page.table);
  const on = page.boxes.filter((b) => b.checked).map((b) => b.name + '=on').join('&');
  assert.strictEqual(page.table.dataset.ndSource, '/ajax/data/device/ports?q=10.0.0.1&' + on);
  assert.strictEqual(page.csv.getAttribute('href'), '/ajax/content/device/ports?q=10.0.0.1&' + on);
  assert.deepStrictEqual(page.replaced, [[{ htmx: true }, '/device?tab=ports&q=10.0.0.1&' + on + '#x']]);
  assert.ok(!on.includes('c_admin'));
});

test('columns_in_place__a_table_port_control_changed__is_asked_for_again_whole', async () => {
  const page = await columnsPage();
  page.table.dataset.ndEdited = '1';
  page.tick('c_power', false);
  await page.ndPorts.applyColumns(page.table);
  assert.deepStrictEqual(page.submits, ['#ports_form submit']);
  assert.strictEqual(page.built.length, 1);
});

test('columns_in_place__c_admin_without_the_reason_dialog__is_asked_for_again_whole', async () => {
  const page = await columnsPage();
  page.tick('c_admin', false);
  await page.ndPorts.applyColumns(page.table);
  assert.strictEqual(page.built.length, 2, 'turned off in place');
  delete page.byId.nd_portlog;
  page.tick('c_admin', true);
  await page.ndPorts.applyColumns(page.table);
  assert.deepStrictEqual(page.submits, ['#ports_form submit'], 'but on again only with a frame drawn under it');
});

test('columns_in_place__an_answer_with_other_ports__is_asked_for_again_whole', async () => {
  const page = await columnsPage({ partial: () => ({ rows: [{ port: 'Gi1/1' }], meta: {} }) });
  page.tick('c_descr', true);
  await page.ndPorts.applyColumns(page.table);
  assert.deepStrictEqual(page.submits, ['#ports_form submit']);
  assert.strictEqual(page.built.length, 1);
});

test('columns_in_place__an_answer_for_a_pane_since_replaced__is_dropped', async () => {
  let release;
  const page = await columnsPage({
    partial: partialAnswer(() => ({ descr: 'late' }))
  });
  const wait = new Promise((resolve) => { release = resolve; });
  page.window.ndRequest.getJSON = (url) => { page.requests.push(url); return wait.then(partialAnswer(() => ({ descr: 'late' }))); };
  page.tick('c_descr', true);
  const done = page.ndPorts.applyColumns(page.table);
  page.table.isConnected = false;
  release();
  await done;
  assert.strictEqual(page.built.length, 1);
  assert.deepStrictEqual(page.submits, []);
  assert.strictEqual(page.built[0].data[0].descr, undefined);
});

test('columns_in_place__clicks_in_a_row__cost_one_request_per_missing_column', async () => {
  let page;
  let calls = 0;
  page = await columnsPage({
    partial: partialAnswer((r) => {
      // ticked, unticked and ticked again while the first request is out
      if (r === fixture.rows[0] && calls++ === 0) {
        page.tick('c_mtu', true);
        page.ndPorts.applyColumns(page.table);
        page.tick('c_mtu', false);
        page.ndPorts.applyColumns(page.table);
        page.tick('c_mtu', true);
        page.ndPorts.applyColumns(page.table);
      }
      return { descr: r.port, mtu: 1500 };
    })
  });
  page.tick('c_descr', true);
  page.tick('c_ssid', false);
  await page.ndPorts.applyColumns(page.table);
  await page.ndPorts.applyColumns(page.table);
  assert.deepStrictEqual(page.requests.slice(1), [
    '/ajax/data/device/ports?q=10.0.0.1&c_descr=on',
    '/ajax/data/device/ports?q=10.0.0.1&c_mtu=on'
  ]);
  const last = page.built[page.built.length - 1];
  assert.deepStrictEqual(last.columns.length, 1 + fixture.columns.length + 1, 'with Description and MTU, without SSID');
});

test('columns_in_place__a_box_ticked_while_the_rows_load__applies_once_they_are_in', async () => {
  let release;
  const wait = new Promise((resolve) => { release = resolve; });
  const boxes = ['c_admin'].concat(colNames(fixture.meta.choices)).map((name) => ({
    name, checked: Boolean(fixture.meta.params[name])
  }));
  const table = frame();
  table.dataset.ndLoader = 'ports';
  table.dataset.ndLoaderStarted = '1';
  const document = {
    querySelectorAll: () => boxes,
    querySelector: (sel) => (sel === '#ports_pane table[data-nd-loader="ports"]' ? table : null),
    getElementById: () => null
  };
  const h = load({ document, answer: () => wait.then(() => clone(fixture)) });
  const loading = h.ndTables.loaders.ports(table, null, h.helpers);
  boxes.find((b) => b.name === 'c_power').checked = false;
  h.ndPorts.onColumnChange({ target: { matches: (sel) => sel === '#ports_form #nd_columns input[type=checkbox]' } });
  h.ndPorts.onColumnChange({ target: { matches: () => false } });
  assert.strictEqual(table.dataset.ndColumnsPending, '1');
  release();
  await loading;
  await settle();
  assert.strictEqual(h.built.length, 2);
  assert.strictEqual(h.built[1].columns.length, fixture.columns.length, 'drawn again without PoE');
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

// --- external links, drawn here ----------------------------------------------

const LINK_META = {
  links: [
    { url: 'https://g/d?dev=[% device %]&host=[%hostname%]&p=[%  port  %]&m=[% mac %]&i=[% ifindex %]', displayname: 'Graphs <1>' },
    { url: 'https://admin/[% fqdn %]/[% unknown %]', displayname: 'Admin' }
  ],
  link_vars: { device: '192.0.2.1', fqdn: 'sw1.example.com', sysname: 'sw%201', hostname: 'sw1' }
};

test('links__urls_of_the_ports_variables__are_drawn_with_the_values_the_server_would_have_escaped', () => {
  const { ndPorts } = load();
  const ctx = { urls: URLS, meta: Object.assign(clone(fixture.meta), clone(LINK_META)) };
  const row = { port: "Gi1/0/1 (a)!*'", mac: 'aa:bb:cc:00:00:01', ifindex: 10101 };
  const html = ndPorts.columnFor('c_links', ctx).html(row, ctx);
  assert.ok(html.includes('href="https://g/d?dev=192.0.2.1&amp;host=sw1&amp;p=Gi1%2F0%2F1%20%28a%29%21%2A%27&amp;m=aa%3Abb%3Acc%3A00%3A00%3A01&amp;i=10101"'), html);
  assert.ok(html.includes('href="https://admin/sw1.example.com/"'), 'a variable it has no value for is empty: ' + html);
  assert.ok(html.includes('</i> Graphs &lt;1&gt;</span>'), 'the name is escaped: ' + html);
  assert.ok(html.includes('target="_blank"') && html.includes('badge text-bg-secondary'));
  assert.strictEqual(ndPorts.columnFor('c_links', ctx).value(row, ctx), 'Graphs &lt;1&gt; Admin', 'its text, as the other columns have it');
});

test('links__a_link_the_acl_hides_from_a_port__is_not_drawn_for_it', () => {
  const { ndPorts } = load();
  const ctx = { urls: URLS, meta: Object.assign(clone(fixture.meta), clone(LINK_META)) };
  const html = ndPorts.columnFor('c_links', ctx).html({ port: 'Vlan10', links_off: [0] }, ctx);
  assert.ok(!html.includes('Graphs') && html.includes('Admin'), html);
});

test('links__without_links_in_meta__the_server_drew_the_column_and_it_is_placed_as_it_is', () => {
  const { ndPorts } = load();
  const ctx = { urls: URLS, meta: clone(fixture.meta) };
  assert.strictEqual(ndPorts.columnFor('c_links', ctx).html({ port: 'a', cells: { c_links: '<a>x</a>' } }, ctx), '<a>x</a>');
});

test('links__ttUri__escapes_what_the_uri_filter_does', () => {
  const { ndPorts } = load();
  assert.strictEqual(ndPorts.ttUri("a b!*'()~._-/é"), 'a%20b%21%2A%27%28%29~._-%2F%C3%A9');
  assert.strictEqual(ndPorts.ttUri(undefined), '');
});
