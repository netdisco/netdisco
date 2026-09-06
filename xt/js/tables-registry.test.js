// Guards the registry and the initializer in netdisco-tables.js. The
// renderers used to be 155 inline closures in fragment templates, outside
// CodeQL and outside any test; each is now a named function, and each name a
// fragment can ask for is asserted to exist here.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const source = fs.readFileSync(
  path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco-tables.js'), 'utf8');

// Load the file in a scope with the globals it touches stubbed. The three
// DataTable.render entries mirror the vendored 2.3.8 shapes read from
// share/public/javascripts/jquery.dataTables.min.js: text() and number()
// return an object keyed by render type (falling back to the raw value for
// a type they don't name), datetime() returns a callable directly.
function load({ built = [] } = {}) {
  const DataTable = function (el, config) { built.push({ el, config }); return { api: () => ({}) }; };
  // Matches the vendored escaper (share/public/javascripts/jquery.dataTables.min.js,
  // the function assigned as both DataTable.util.escapeHtml and the body of
  // render.text()): arrays join with a comma, non-strings pass through
  // unescaped, and no quote entity for an apostrophe.
  const esc = (v) => {
    v = Array.isArray(v) ? v.join(',') : v;
    return typeof v === 'string'
      ? v.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
      : v;
  };
  DataTable.util = { escapeHtml: esc };
  DataTable.ext = { search: [] };
  DataTable.render = {
    text: function () { return { display: esc, filter: esc }; },
    number: function (thousands, decimal, precision) {
      return {
        display: function (data) {
          if (typeof data !== 'number' && typeof data !== 'string') return data;
          if (data === '' || data === null) return data;
          var n = Number(data);
          var fixed = Math.abs(n).toFixed(precision).split('.');
          return (n < 0 ? '-' : '') + fixed[0].replace(/\B(?=(\d{3})+(?!\d))/g, thousands) + (fixed[1] ? decimal + fixed[1] : '');
        },
      };
    },
    // Mirrors the real datetime() for the shape this file exercises: a
    // callable returned directly, blanking null/empty, formatting a display
    // value through the given format. Does not mirror it for 'sort'/'type':
    // the vendored function returns a parsed moment object for 'sort' and the
    // registered type name for 'type', used for correct column sorting; this
    // mock returns the raw value for both, which no assertion here depends on.
    datetime: function (format) {
      return function (data, type) {
        if (data == null || data === '') return '';
        if (type === 'sort' || type === 'type') return data;
        return moment(data).format(format);
      };
    },
  };
  const document = { body: { dataset: {} }, querySelectorAll: () => [], getElementById: () => null };
  const window = {};
  const moment = (d) => ({ format: () => 'M:' + d });
  const fn = new Function('DataTable', 'document', 'window', 'moment', source + '\nreturn ndTables;');
  return fn(DataTable, document, window, moment);
}

const URLS = { device: '/device', device_ports: '/device?tab=ports', search_device: '/search?tab=device', search_node: '/search?tab=node', search: '/search', report_moduleinventory: '/report/moduleinventory', report_nodevendor: '/report/nodevendor', report_portssid: '/report/portssid', report_netbios: '/report/netbios', uri_base: '' };

test('renderers__escape__escapes_and_passes_null_through', () => {
  const t = load();
  const r = t.renderers.escape({}, URLS);
  assert.strictEqual(r('<b>', 'display', {}), '&lt;b&gt;');
  // DataTable.render.text() leaves a null cell as null rather than blanking
  // it; DataTables' own _fnGetCellData blanks a null display value to "" for
  // every renderer shape, so the browser is unaffected.
  assert.strictEqual(r(null, 'display', {}), null);
});

test('renderers__number__inserts_thousands_separators', () => {
  const r = load().renderers.number({}, URLS);
  assert.strictEqual(r(1234567, 'display', {}), '1,234,567');
});

test('renderers__dateTime__formats_through_moment_and_blanks_null', () => {
  const r = load().renderers.dateTime({}, URLS);
  assert.strictEqual(r('2026-09-04T10:00:00', 'display', {}), 'M:2026-09-04T10:00:00');
  assert.strictEqual(r(null, 'display', {}), '');
});

test('renderers__devicePortsLink__builds_the_ports_link_from_row_keys', () => {
  const r = load().renderers.devicePortsLink({ q: 'ip', f: 'data', flags: 'c_nodes=on' }, URLS);
  const out = r('Gi1/0/1', 'display', { ip: '10.0.0.1' });
  assert.strictEqual(out, '<a href="/device?tab=ports&q=10.0.0.1&f=Gi1%2F0%2F1&c_nodes=on">Gi1/0/1</a>');
});

test('renderers__devicePortsLinkNamed__labels_with_the_device_and_a_suffix', () => {
  const r = load().renderers.devicePortsLinkNamed({ q: 'data', f: 'port.port', flags: 'c_nodes=on&n_ssid=on', dns: 'device.dns', name: 'device.name', ip: 'ip', suffix: 'port.port' }, URLS);
  const out = r('10.0.0.1', 'display', { ip: '10.0.0.1', device: { dns: 'sw1.example' }, port: { port: 'Gi1' } });
  assert.strictEqual(out, '<a href="/device?tab=ports&q=10.0.0.1&f=Gi1&c_nodes=on&n_ssid=on">sw1.example(Gi1)</a>');
});

test('renderers__reportLink__sends_the_blank_token_for_an_empty_value', () => {
  const r = load().renderers.reportLink({ report: 'report_netbios', param: 'domain', blankText: '(Blank Domain)' }, URLS);
  assert.strictEqual(r('', 'display', {}), '<a href="/report/netbios?domain=blank">(Blank Domain)</a>');
});

test('renderers__ipInventoryAddress__links_a_node_a_device_or_nothing', () => {
  const r = load().renderers.ipInventoryAddress({}, URLS);
  assert.strictEqual(r('10.0.0.9', 'display', { time_last: 't', node: true, active: true }), '<a href="/search?tab=node&q=10.0.0.9">10.0.0.9</a>');
  assert.strictEqual(r('10.0.0.9', 'display', { time_last: 't', node: false }), '<a href="/search?tab=device&q=10.0.0.9">10.0.0.9</a>');
  assert.strictEqual(r('10.0.0.9', 'display', {}), '10.0.0.9');
});

test('renderers__devicePortsLink__for_sorting_returns_the_escaped_value', () => {
  const r = load().renderers.devicePortsLink({ q: 'ip', f: 'data' }, URLS);
  assert.strictEqual(r('a<b', 'sort', { ip: '10.0.0.1' }), 'a&lt;b');
});

test('renderers__deviceLink__labels_with_the_device_name_and_an_optional_tab_and_suffix', () => {
  const r = load().renderers.deviceLink({ tab: 'ports', suffix: 'model' }, URLS);
  const out = r('10.0.0.1', 'display', { dns: 'sw1.example', model: 'WS-C3750' });
  assert.strictEqual(out, '<a href="/device?tab=ports&q=10.0.0.1">sw1.example (WS-C3750)</a>');
});

test('renderers__searchDeviceLink__basic_also_and_notSet', () => {
  const t = load();
  assert.strictEqual(t.renderers.searchDeviceLink({}, URLS)('10.0.0.1', 'display', {}), '<a href="/search?tab=device&q=10.0.0.1">10.0.0.1</a>');
  assert.strictEqual(t.renderers.searchDeviceLink({ notSet: 'Not set' }, URLS)('', 'display', {}), 'Not set');
  assert.strictEqual(t.renderers.searchDeviceLink({ also: 'ip' }, URLS)('10.0.0.1', 'display', {}), '<a href="/search?tab=device&q=10.0.0.1&ip=10.0.0.1">10.0.0.1</a>');
  assert.strictEqual(t.renderers.searchDeviceLink({ label: { dns: 'dns' } }, URLS)('10.0.0.1', 'display', { dns: 'sw1.example' }), '<a href="/search?tab=device&q=10.0.0.1">sw1.example</a>');
});

test('renderers__searchNodeLink__the_flag_combinations_and_the_archived_marker', () => {
  const t = load();
  // archived: adds the &archived=on flag and the single-marker HTML.
  assert.strictEqual(
    t.renderers.searchNodeLink({ archived: true }, URLS)('AA:BB:CC', 'display', { active: false }),
    '<a href="/search?tab=node&q=AA%3ABB%3ACC&archived=on">AA:BB:CC&nbsp;<i class="fas fa-book text-warning"></i>&nbsp;</a>',
  );
  // mark without archived: the marker only, no flag.
  assert.strictEqual(
    t.renderers.searchNodeLink({ mark: true }, URLS)('AA:BB:CC', 'display', { active: false }),
    '<a href="/search?tab=node&q=AA%3ABB%3ACC">AA:BB:CC&nbsp;&nbsp;<i class="fas fa-book text-warning"></i> </a>',
  );
  // an active row gets neither, regardless of archived/mark.
  assert.strictEqual(
    t.renderers.searchNodeLink({ archived: true }, URLS)('AA:BB:CC', 'display', { active: true }),
    '<a href="/search?tab=node&q=AA%3ABB%3ACC">AA:BB:CC</a>',
  );
  // onlyIf gates the link entirely when the named row key is falsy.
  assert.strictEqual(t.renderers.searchNodeLink({ onlyIf: 'known' }, URLS)('AA:BB', 'display', { known: false, active: true }), 'AA:BB');
  // domainPrefix prepends the escaped NetBIOS domain outside the link.
  assert.strictEqual(
    t.renderers.searchNodeLink({ domainPrefix: true }, URLS)('AA:BB', 'display', { domain: 'CORP', active: true }),
    '\\\\CORP\\<a href="/search?tab=node&q=AA%3ABB">AA:BB</a>',
  );
});

test('renderers__subnetLink__admin_adds_tool_links_that_a_non_admin_does_not_get', () => {
  const t = load();
  const nonAdmin = t.renderers.subnetLink({}, URLS, { dataset: { ndAdmin: '0' } })('10.0.0.0/24');
  assert.strictEqual(nonAdmin, '<a href="/search?tab=device&q=10.0.0.0%2F24&ip=10.0.0.0%2F24">10.0.0.0/24</a>');
  const admin = t.renderers.subnetLink({}, URLS, { dataset: { ndAdmin: '1' } })('10.0.0.0/24');
  assert.ok(admin.includes('/report/ipinventory?subnet=10.0.0.0%2F24'), 'admin gets the inventory shortcut');
  assert.ok(admin.includes('/?device=10.0.0.0%2F24'), 'admin gets the discover shortcut');
  assert.ok(admin.endsWith(nonAdmin), 'admin still gets the same search link every viewer gets');
});

test('renderers__escape__for_sort__falls_back_to_the_raw_value', () => {
  const r = load().renderers.escape({}, URLS);
  assert.strictEqual(r('<b>', 'sort', {}), '<b>');
});

test('renderers__number__for_filter__falls_back_to_the_raw_value', () => {
  const r = load().renderers.number({}, URLS);
  assert.strictEqual(r(1234567, 'filter', {}), 1234567);
});

test('renderers__powerPair__escapes_both_values', () => {
  const r = load().renderers.powerPair({}, URLS);
  assert.strictEqual(r('<a>', 'display', { power2: '<b>' }), '&lt;a&gt; / &lt;b&gt;');
});

test('renderers__join__without_a_key__throws_naming_the_problem', () => {
  const t = load();
  assert.throws(() => t.renderers.join({}, URLS), /"key"/);
});

test('renderers__a_missing_data_nd_urls_key__throws_naming_the_key_and_the_renderer', () => {
  const t = load();
  assert.throws(() => t.renderers.deviceLink({}, {}), /renderer deviceLink needs data-nd-urls key "device"/);
});

test('callbacks__groupRows__escapes_the_group_value_unless_html_is_set', () => {
  const t = load();
  const rows = [{ insertAdjacentHTML: (pos, html) => rows.calls.push(html) }];
  rows.calls = [];
  const api = {
    rows: () => ({ nodes: () => rows }),
    column: () => ({ data: () => ({ each: (fn) => fn('<b>Group</b>', 0) }) }),
  };
  t.callbacks.groupRows({ colspan: 3 }).call({ api: () => api });
  assert.strictEqual(rows.calls[0], '<tr class="group"><td colspan="3">&lt;b&gt;Group&lt;/b&gt;</td></tr>');
});

test('callbacks__groupRows__html_true__does_not_escape_a_DOM_sourced_cell', () => {
  const t = load();
  const rows = [{ insertAdjacentHTML: (pos, html) => rows.calls.push(html) }];
  rows.calls = [];
  const api = {
    rows: () => ({ nodes: () => rows }),
    column: () => ({ data: () => ({ each: (fn) => fn('<b>Group</b>', 0) }) }),
  };
  t.callbacks.groupRows({ colspan: 3, html: true }).call({ api: () => api });
  assert.strictEqual(rows.calls[0], '<tr class="group"><td colspan="3"><b>Group</b></td></tr>');
});

test('init__a_table_that_throws_during_build__still_builds_the_rest', () => {
  const built = [];
  const t = load({ built });
  const errors = [];
  const originalError = console.error;
  console.error = (e) => errors.push(e);
  try {
    const badTable = { classList: { contains: () => false }, dataset: { ndTable: '{"columns":[{"render":"nope"}]}', ndUrls: '{}' }, ownerDocument: { getElementById: () => null } };
    const goodTable = { classList: { contains: () => false }, dataset: { ndTable: '{}', ndUrls: '{}' }, ownerDocument: { getElementById: () => null } };
    t.init({ querySelectorAll: () => [badTable, goodTable] });
  } finally {
    console.error = originalError;
  }
  assert.strictEqual(built.length, 1, 'the table after the bad one still gets built');
  assert.strictEqual(errors.length, 1, 'the bad table logs once rather than throwing out of init');
});

test('renderers__deviceName__prefers_dns_then_name_then_ip', () => {
  const r = load().renderers.deviceName({ dns: 'dns', name: 'name', ip: 'ip' }, URLS);
  assert.strictEqual(r(null, 'display', { dns: 'sw1.example', name: 'sw1', ip: '10.0.0.1' }), 'sw1.example');
  assert.strictEqual(r(null, 'display', { name: 'sw1', ip: '10.0.0.1' }), 'sw1');
  assert.strictEqual(r(null, 'display', { ip: '10.0.0.1' }), '10.0.0.1');
});

test('renderers__age__shows_the_text_and_sorts_by_the_stamp', () => {
  const r = load().renderers.age({ stamp: 'time_last' }, URLS);
  assert.strictEqual(r('2:30:00', 'display', { time_last: '2026-09-04' }), '2 hours 30 mins');
  assert.strictEqual(r('2:30:00', 'sort', { time_last: '2026-09-04' }), '2026-09-04');
  assert.strictEqual(r(null, 'display', {}), 'Never');
});

test('resolve__a_string__is_a_renderer_with_no_args', () => {
  const t = load();
  const r = t.resolve('escape', URLS, {});
  assert.strictEqual(r('x', 'display', {}), 'x');
});

test('resolve__an_unknown_name__throws_naming_it', () => {
  const t = load();
  assert.throws(() => t.resolve('nope', URLS, {}), /nope/);
});

test('build__merges_the_defaults_and_resolves_render_names', () => {
  const built = [];
  const t = load({ built });
  const table = {
    id: 'data-table',
    dataset: { ndTable: JSON.stringify({ columns: [{ data: 'ip', render: 'escape' }], order: [[0, 'asc']] }), ndUrls: JSON.stringify(URLS) },
    ownerDocument: { getElementById: () => null },
  };
  t.build(table);
  assert.strictEqual(built.length, 1);
  const config = built[0].config;
  assert.strictEqual(config.pageLength, 10, 'shipped default when body carries none');
  assert.strictEqual(config.pagingType, 'simple_numbers');
  assert.strictEqual(typeof config.columns[0].render, 'function');
  assert.deepStrictEqual(config.order, [[0, 'asc']]);
});

test('build__with_a_data_block__feeds_it_as_the_row_array', () => {
  const built = [];
  const t = load({ built });
  const table = {
    id: 'data-table',
    dataset: { ndTable: '{"columns":[{"data":"ip","render":"escape"}]}', ndUrls: '{}', ndData: '#nd-results' },
    ownerDocument: { getElementById: (id) => (id === 'nd-results' ? { textContent: '[{"ip":"10.0.0.1"}]' } : null) },
  };
  t.build(table);
  assert.deepStrictEqual(built[0].config.data, [{ ip: '10.0.0.1' }]);
});

test('build__stateSaveParams__never_saves_search_or_page', () => {
  const built = [];
  load({ built }).build({ id: 'x', dataset: { ndTable: '{}', ndUrls: '{}' }, ownerDocument: { getElementById: () => null } });
  const data = { search: { search: 'leak' }, start: 30, order: [[1, 'asc']] };
  built[0].config.stateSaveParams({}, data);
  assert.strictEqual(data.search.search, '');
  assert.strictEqual(data.start, 0);
  assert.deepStrictEqual(data.order, [[1, 'asc']], 'order is kept unless the table asks otherwise');
});

test('build__customReport__drops_the_saved_order', () => {
  const built = [];
  load({ built }).build({ id: 'x', dataset: { ndTable: '{"customReport":true}', ndUrls: '{}' }, ownerDocument: { getElementById: () => null } });
  const data = { search: { search: '' }, start: 0, order: [[1, 'asc']] };
  built[0].config.stateSaveParams({}, data);
  assert.strictEqual(data.order, '');
});

test('build__initComplete__resolves_a_named_callback', () => {
  const built = [];
  load({ built }).build({ id: 'x', dataset: { ndTable: '{"initComplete":"portsCollapse"}', ndUrls: '{}' }, ownerDocument: { getElementById: () => null } });
  assert.strictEqual(typeof built[0].config.initComplete, 'function');
});

test('build__defaults_false__reaches_DataTables_with_none_of_the_shared_keys', () => {
  const built = [];
  load({ built }).build({ id: 'x', dataset: { ndTable: '{"defaults":false,"paging":false}', ndUrls: '{}' }, ownerDocument: { getElementById: () => null } });
  const config = built[0].config;
  assert.strictEqual(config.processing, undefined);
  assert.strictEqual(config.dom, undefined);
  assert.strictEqual(config.language, undefined);
  assert.strictEqual(config.stateSave, undefined);
  assert.strictEqual(config.defaults, undefined, 'the flag itself is consumed, not passed through');
  assert.strictEqual(config.paging, false, 'the table\'s own options still apply');
});

test('build__without_defaults_false__still_gets_the_shared_options', () => {
  const built = [];
  load({ built }).build({ id: 'x', dataset: { ndTable: '{}', ndUrls: '{}' }, ownerDocument: { getElementById: () => null } });
  const config = built[0].config;
  assert.strictEqual(config.processing, true);
  assert.strictEqual(config.stateSave, true);
  assert.strictEqual(typeof config.dom, 'string');
  assert.strictEqual(typeof config.language, 'object');
});

// Every name a fragment can ask for must exist. Reads the templates rather
// than a list kept here, so a fragment naming a renderer that was never
// written fails this test rather than a user's page.
test('fragments__every_render_and_callback_name__is_in_the_registry', () => {
  const t = load();
  const VIEWS = path.join(ROOT, 'share', 'views', 'ajax');
  const names = new Set();
  const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).forEach((e) => {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) return walk(full);
    const text = fs.readFileSync(full, 'utf8');
    for (const m of text.matchAll(/"(?:render|drawCallback|initComplete)"\s*:\s*(?:"([a-zA-Z]+)"|\{[^}]*"name"\s*:\s*"([a-zA-Z]+)")/g)) names.add(m[1] || m[2]);
  });
  walk(VIEWS);
  const missing = [...names].filter((n) => !(n in t.renderers) && !(n in t.callbacks));
  assert.deepStrictEqual(missing, []);
});
