// Guards the registry and the initializer in netdisco-tables.js. Renderers
// are named functions here rather than inline closures in fragment
// templates, which keeps them inside CodeQL's reach and inside test
// coverage; each name a fragment can ask for is asserted to exist here.

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
    // value through the given format, and returning the raw input unchanged
    // for every type, including display, when it fails to parse (matched
    // here by not looking like a date at all). Does not mirror it for
    // 'sort'/'type' on a value that does parse: the vendored function
    // returns a parsed moment object for 'sort' and the registered type name
    // for 'type', used for correct column sorting; this mock returns the raw
    // value for both, which no assertion here depends on.
    datetime: function (format) {
      return function (data, type) {
        if (data == null || data === '') return '';
        if (!/^\d{4}-\d{2}-\d{2}/.test(String(data))) return data;
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

// Shared by both fragment-scanning tests below. An IF/ELSE/END pair wrapping
// optional JSON is stripped to its tag markers alone, always yielding the
// branch that is present in the source; a bare expression standing in for a
// scalar value is replaced with a neutral literal. Only the surrounding JSON
// shape is read here, never the runtime value, so which branch or literal
// does not matter.
// Returns every value of a single-quoted attribute in the text. A value may
// hold a Template Toolkit directive that itself contains a quote, such as
// uri_for('/device'), so this scans character by character and skips each
// [% ... %] whole instead of stopping at the first quote. A plain regex for
// the same job backtracks exponentially on repeated directives.
function attributeValues(text, name) {
  const values = [];
  const marker = name + "='";
  let from = 0;
  for (;;) {
    const start = text.indexOf(marker, from);
    if (start === -1) return values;
    let i = start + marker.length;
    const begin = i;
    while (i < text.length && text[i] !== "'") {
      if (text.startsWith('[%', i)) {
        const close = text.indexOf('%]', i + 2);
        if (close === -1) throw new Error('unclosed directive after ' + marker);
        i = close + 2;
      } else {
        i += 1;
      }
    }
    values.push(text.slice(begin, i));
    from = i + 1;
  }
}

function stripDirectives(text) {
  return text
    .replace(/\[%\s*(?:IF|ELSIF|ELSE|END)\b[^%]*%\]/gi, '')
    .replace(/\[%[^%]*?%\]/g, '0');
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

// devicepoestatus's wattage columns mix whole watts with one-decimal
// readings in the same column; the precision comes from each value's own
// string form rather than a fixed instance, so an integer keeps no decimal
// and a fractional value keeps exactly the decimal places it was given.
test('renderers__number__an_integer__keeps_no_decimal_place', () => {
  const r = load().renderers.number({}, URLS);
  assert.strictEqual(r(20, 'display', {}), '20');
});

test('renderers__number__a_one_decimal_value__keeps_one_decimal_place', () => {
  const r = load().renderers.number({}, URLS);
  assert.strictEqual(r(15.4, 'display', {}), '15.4');
});

test('renderers__number__a_two_decimal_value__groups_thousands_and_keeps_two_decimal_places', () => {
  const r = load().renderers.number({}, URLS);
  assert.strictEqual(r(1234.56, 'display', {}), '1,234.56');
});

test('renderers__number__precision__forces_one_decimal_count_for_every_value', () => {
  const r = load().renderers.number({ precision: 1 }, URLS);
  assert.strictEqual(r(20, 'display', {}), '20.0');
  assert.strictEqual(r(15.44, 'display', {}), '15.4');
});

test('renderers__dateTime__formats_through_moment_and_blanks_null', () => {
  const r = load().renderers.dateTime({}, URLS);
  assert.strictEqual(r('2026-09-04T10:00:00', 'display', {}), 'M:2026-09-04T10:00:00');
  assert.strictEqual(r(null, 'display', {}), '');
});

// The vendored parser returns an unparseable value unchanged, for every type
// including display, and DataTables writes a display value straight to
// innerHTML; escaping only the pass-through case keeps a value that did
// format from being escaped a second time.
test('renderers__dateTime__an_unparseable_value__renders_escaped_for_display', () => {
  const r = load().renderers.dateTime({}, URLS);
  assert.strictEqual(r('<b>', 'display', {}), '&lt;b&gt;');
  assert.strictEqual(r('<b>', 'sort', {}), '<b>');
});

test('renderers__devicePortsLink__builds_the_ports_link_from_row_keys', () => {
  const r = load().renderers.devicePortsLink({ q: 'ip', f: 'data', flags: 'c_nodes=on' }, URLS);
  const out = r('Gi1/0/1', 'display', { ip: '10.0.0.1' });
  assert.strictEqual(out, '<a href="/device?tab=ports&q=10.0.0.1&f=Gi1%2F0%2F1&c_nodes=on">Gi1/0/1</a>');
});

test('renderers__devicePortsLink__text_shows_a_row_key_instead_of_the_cell', () => {
  const r = load().renderers.devicePortsLink({ q: 'ip', f: 'data', text: 'ports.name' }, URLS);
  const out = r('Gi1/0/1', 'display', { ip: '10.0.0.1', ports: { name: 'AP-Lobby' } });
  assert.strictEqual(out, '<a href="/device?tab=ports&q=10.0.0.1&f=Gi1%2F0%2F1">AP-Lobby</a>');
});

test('renderers__devicePortsLink__qFallback__is_used_only_when_q_is_empty', () => {
  const r = load().renderers.devicePortsLink({ q: 'left_dns', f: 'data', qFallback: 'left_ip' }, URLS);
  assert.strictEqual(
    r('Gi1', 'display', { left_dns: '', left_ip: '10.0.0.1' }),
    '<a href="/device?tab=ports&q=10.0.0.1&f=Gi1">Gi1</a>',
  );
  assert.strictEqual(
    r('Gi1', 'display', { left_dns: 'sw1.example', left_ip: '10.0.0.1' }),
    '<a href="/device?tab=ports&q=sw1.example&f=Gi1">Gi1</a>',
  );
});

test('renderers__devicePortsLink__number__formats_the_shown_text_with_thousands_separators', () => {
  const r = load().renderers.devicePortsLink({ q: 'ip', f: 'data', always: true, number: true }, URLS);
  assert.strictEqual(r(1234, 'display', { ip: '10.0.0.1' }), '<a href="/device?tab=ports&q=10.0.0.1&f=1234">1,234</a>');
});

test('renderers__devicePortsLink__text_and_number_together__throws', () => {
  const t = load();
  assert.throws(() => t.renderers.devicePortsLink({ q: 'ip', f: 'data', text: 'x', number: true }, URLS), /"text" and "number"/);
});

test('renderers__devicePortsLink__descr__adds_a_second_line_from_a_row_key', () => {
  const r = load().renderers.devicePortsLink({ q: 'left_ip', f: 'data', descr: 'left_port_descr' }, URLS);
  assert.strictEqual(
    r('Gi1', 'display', { left_ip: '10.0.0.1', left_port_descr: 'uplink' }),
    '<a href="/device?tab=ports&q=10.0.0.1&f=Gi1">Gi1</a><br />uplink',
  );
  // a missing row key adds an empty second line rather than the word "undefined"
  assert.strictEqual(
    r('Gi1', 'display', { left_ip: '10.0.0.1' }),
    '<a href="/device?tab=ports&q=10.0.0.1&f=Gi1">Gi1</a><br />',
  );
});

test('renderers__devicePortsLinkNamed__labels_with_the_device_and_a_suffix', () => {
  const r = load().renderers.devicePortsLinkNamed({ q: 'data', f: 'port.port', flags: 'c_nodes=on&n_ssid=on', dns: 'device.dns', name: 'device.name', ip: 'ip', suffix: 'port.port' }, URLS);
  const out = r('10.0.0.1', 'display', { ip: '10.0.0.1', device: { dns: 'sw1.example' }, port: { port: 'Gi1' } });
  assert.strictEqual(out, '<a href="/device?tab=ports&q=10.0.0.1&f=Gi1&c_nodes=on&n_ssid=on">sw1.example(Gi1)</a>');
});

test('renderers__devicePortsLinkNamed__suffix_data__shows_the_cell_rather_than_a_row_key', () => {
  const r = load().renderers.devicePortsLinkNamed({ q: 'switch', f: 'data', flags: 'c_nodes=on', dns: 'dns', name: 'name', ip: 'switch', suffix: 'data' }, URLS);
  const out = r('Gi1/0/1', 'display', { switch: '10.0.0.1', dns: 'sw1.example' });
  assert.strictEqual(out, '<a href="/device?tab=ports&q=10.0.0.1&f=Gi1%2F0%2F1&c_nodes=on">sw1.example(Gi1/0/1)</a>');
});

// Through resolve(), and with dns/name/ip nested under "label" as
// report/nodevendor and report/portssid write it in their own
// data-nd-table JSON, rather than passed as top-level keys straight to the
// factory: the dispatch key "name" (here "devicePortsLinkNamed") and the
// row-key argument "name" would otherwise collide inside the same JSON
// object, as deviceLabel's own doc comment explains.
test('renderers__devicePortsLinkNamed__label_nested__renders_through_resolveRenderer', () => {
  const fn = load().resolveRenderer({
    name: 'devicePortsLinkNamed', q: 'switch', f: 'data', flags: 'c_nodes=on',
    label: { dns: 'dns', name: 'name', ip: 'switch' }, suffix: 'data',
  }, URLS, {});
  const out = fn('Gi1/0/1', 'display', { switch: '10.0.0.1', dns: '', name: 'sw1' });
  assert.strictEqual(out, '<a href="/device?tab=ports&q=10.0.0.1&f=Gi1%2F0%2F1&c_nodes=on">sw1(Gi1/0/1)</a>');
});

// No blankText named: the href still carries the "blank" token (a better
// target than the empty parameter the removed closures sent), but the label
// is empty, matching those closures' own `data || ''`.
test('renderers__reportLink__no_blankText__empty_value_renders_empty_text_with_the_blank_token_in_the_href', () => {
  const r = load().renderers.reportLink({ report: 'report_netbios', param: 'domain' }, URLS);
  assert.strictEqual(r('', 'display', {}), '<a href="/report/netbios?domain=blank"></a>');
});

test('renderers__reportLink__blankText__still_wins_over_the_blank_token_for_an_empty_value', () => {
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

// Shared by the toggleOrder tests below: a minimal api mock carrying just
// the surface bindGroupOrderToggle and groupRows touch.
function groupOrderApi(order) {
  const listeners = {};
  const body = { addEventListener: (type, fn) => { listeners[type] = fn } };
  const table = { dataset: {} };
  const rows = [{ insertAdjacentHTML: () => {} }];
  const api = {
    rows: () => ({ nodes: () => rows }),
    column: () => ({ data: () => ({ each: (fn) => fn('g', 0) }) }),
    table: () => ({ node: () => table, body: () => body }),
    order: (v) => { if (v === undefined) return order; order = [v]; return api },
    draw: () => api,
  };
  return { api, listeners, currentOrder: () => order };
}

test('callbacks__groupRows__toggleOrder__a_click_on_a_group_row_flips_the_order_and_redraws', () => {
  const t = load();
  const { api, listeners, currentOrder } = groupOrderApi([[0, 'asc']]);
  t.callbacks.groupRows({ colspan: 2, toggleOrder: true }).call({ api: () => api });
  assert.ok(listeners.click, 'a click listener is bound on tbody');
  listeners.click({ target: { closest: (sel) => (sel === 'tr.group' ? {} : null) } });
  assert.deepStrictEqual(currentOrder(), [[0, 'desc']]);
  // a click outside a group row leaves the order untouched
  listeners.click({ target: { closest: () => null } });
  assert.deepStrictEqual(currentOrder(), [[0, 'desc']]);
});

test('callbacks__groupRows__without_toggleOrder__binds_no_listener', () => {
  const t = load();
  const { api, listeners } = groupOrderApi([[0, 'asc']]);
  t.callbacks.groupRows({ colspan: 2 }).call({ api: () => api });
  assert.strictEqual(listeners.click, undefined);
});

test('callbacks__groupRows__toggleOrder__a_second_draw__does_not_bind_a_second_listener', () => {
  const t = load();
  const { api } = groupOrderApi([[0, 'asc']]);
  const callback = t.callbacks.groupRows({ colspan: 2, toggleOrder: true });
  let bindCount = 0;
  const body = api.table().body();
  const originalAdd = body.addEventListener;
  body.addEventListener = (type, fn) => { bindCount++; originalAdd(type, fn) };
  callback.call({ api: () => api });
  callback.call({ api: () => api });
  assert.strictEqual(bindCount, 1);
});

// Shared by the groupDeviceRows tests below: a minimal api mock carrying
// one group of one row, whose data api.row(i).data() returns directly
// (unlike groupRows, whose group value comes from the column-0 read alone,
// groupDeviceRows builds its label from the whole row).
function groupDeviceApi(rowData, order) {
  const listeners = {};
  const body = { addEventListener: (type, fn) => { listeners[type] = fn } };
  const table = { dataset: {} };
  const calls = [];
  const rows = [{ insertAdjacentHTML: (pos, html) => calls.push(html) }];
  const api = {
    rows: () => ({ nodes: () => rows }),
    column: () => ({ data: () => ({ each: (fn) => fn('g', 0) }) }),
    row: () => ({ data: () => rowData }),
    table: () => ({ node: () => table, body: () => body }),
    order: (v) => { if (v === undefined) return order; order = [v]; return api },
    draw: () => api,
  };
  return { api, listeners, calls, currentOrder: () => order };
}

// A second api shape for the tests below: several rows in row order, each
// with its own column-0 group value and row data, rather than groupDeviceApi's
// single fixed row repeated for every read.
function groupDeviceApiForGroups(entries) {
  const calls = [];
  const rows = entries.map(() => ({ insertAdjacentHTML: (pos, html) => calls.push(html) }));
  const api = {
    rows: () => ({ nodes: () => rows }),
    column: () => ({ data: () => ({ each: (fn) => entries.forEach((e, i) => fn(e.group, i)) }) }),
    row: (i) => ({ data: () => entries[i].row }),
    table: () => ({ node: () => ({ dataset: {} }), body: () => ({ addEventListener: () => {} }) }),
  };
  return { api, calls };
}

test('callbacks__groupDeviceRows__two_rows_in_the_same_group__inserts_exactly_one_header', () => {
  const t = load();
  const row = { ip: '10.0.0.1', dns: 'sw1.example', model: 'M' };
  const { api, calls } = groupDeviceApiForGroups([
    { group: '10.0.0.1', row },
    { group: '10.0.0.1', row },
  ]);
  t.callbacks.groupDeviceRows({ colspan: 5, nameKey: 'device_name' }, URLS).call({ api: () => api });
  assert.strictEqual(calls.length, 1);
});

test('callbacks__groupDeviceRows__two_different_groups__inserts_two_headers', () => {
  const t = load();
  const { api, calls } = groupDeviceApiForGroups([
    { group: '10.0.0.1', row: { ip: '10.0.0.1', dns: 'sw1.example', model: 'M' } },
    { group: '10.0.0.2', row: { ip: '10.0.0.2', dns: 'sw2.example', model: 'M' } },
  ]);
  t.callbacks.groupDeviceRows({ colspan: 5, nameKey: 'device_name' }, URLS).call({ api: () => api });
  assert.strictEqual(calls.length, 2);
});

test('callbacks__groupDeviceRows__without_a_nameKey__throws_naming_the_problem', () => {
  const t = load();
  assert.throws(() => t.callbacks.groupDeviceRows({ colspan: 5 }, URLS), /"nameKey"/);
});

test('callbacks__groupDeviceRows__labels_with_dns_when_present', () => {
  const t = load();
  const { api, calls } = groupDeviceApi({ ip: '10.0.0.1', dns: 'sw1.example', device_name: 'SW1', model: 'WS-C3750', location: '' });
  t.callbacks.groupDeviceRows({ colspan: 5, nameKey: 'device_name' }, URLS).call({ api: () => api });
  assert.strictEqual(
    calls[0],
    '<tr class="group"><td colspan="5">Device: <a href="/device?tab=details&q=10.0.0.1">sw1.example (10.0.0.1) </a> Model: WS-C3750</td></tr>',
  );
});

test('callbacks__groupDeviceRows__falls_back_to_the_named_key_when_dns_is_absent', () => {
  const t = load();
  const { api, calls } = groupDeviceApi({ ip: '10.0.0.2', device_name: 'SW2', model: '', location: '' });
  t.callbacks.groupDeviceRows({ colspan: 5, nameKey: 'device_name' }, URLS).call({ api: () => api });
  assert.strictEqual(
    calls[0],
    '<tr class="group"><td colspan="5">Device: <a href="/device?tab=details&q=10.0.0.2">SW2 (10.0.0.2) </a> Model: </td></tr>',
  );
});

test('callbacks__groupDeviceRows__falls_back_to_ip_with_no_parenthetical_when_neither_dns_nor_name_is_set', () => {
  const t = load();
  const { api, calls } = groupDeviceApi({ ip: '10.0.0.3', model: 'X', location: '' });
  t.callbacks.groupDeviceRows({ colspan: 5, nameKey: 'device_name' }, URLS).call({ api: () => api });
  assert.strictEqual(
    calls[0],
    '<tr class="group"><td colspan="5">Device: <a href="/device?tab=details&q=10.0.0.3">10.0.0.3</a> Model: X</td></tr>',
  );
});

test('callbacks__groupDeviceRows__location__shown_only_when_set', () => {
  const t = load();
  const withLocation = groupDeviceApi({ ip: '10.0.0.4', dns: 'sw4.example', model: 'M', location: 'DC1' });
  t.callbacks.groupDeviceRows({ colspan: 5, nameKey: 'device_name' }, URLS).call({ api: () => withLocation.api });
  assert.strictEqual(
    withLocation.calls[0],
    '<tr class="group"><td colspan="5">Device: <a href="/device?tab=details&q=10.0.0.4">sw4.example (10.0.0.4) </a> Model: M Location: DC1</td></tr>',
  );

  const withoutLocation = groupDeviceApi({ ip: '10.0.0.5', dns: 'sw5.example', model: 'M' });
  t.callbacks.groupDeviceRows({ colspan: 5, nameKey: 'device_name' }, URLS).call({ api: () => withoutLocation.api });
  assert.strictEqual(
    withoutLocation.calls[0],
    '<tr class="group"><td colspan="5">Device: <a href="/device?tab=details&q=10.0.0.5">sw5.example (10.0.0.5) </a> Model: M</td></tr>',
  );
});

test('callbacks__groupDeviceRows__toggleOrder__a_click_on_a_group_row_flips_the_order_and_redraws', () => {
  const t = load();
  const { api, listeners, currentOrder } = groupDeviceApi({ ip: '10.0.0.6', dns: 'sw6.example', model: 'M' }, [[0, 'asc']]);
  t.callbacks.groupDeviceRows({ colspan: 5, nameKey: 'device_name', toggleOrder: true }, URLS).call({ api: () => api });
  assert.ok(listeners.click, 'a click listener is bound on tbody');
  listeners.click({ target: { closest: (sel) => (sel === 'tr.group' ? {} : null) } });
  assert.deepStrictEqual(currentOrder(), [[0, 'desc']]);
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

// Through resolve(), not the factory directly: a fragment's spec object IS
// the args object, so its own dispatch key ("name": "deviceName") must not
// shadow deviceLabel's row-key argument of the same name.
// No tier named, so deviceLabel takes the full dns/name/ip fallback; before
// resolveRenderer() stripped its own dispatch key, args.name here was the
// string "deviceName" rather than unset, which this path reads as the row
// key "deviceName" instead of falling through to "name".
test('resolveRenderer__an_object_spec__does_not_leak_its_own_dispatch_name_into_args', () => {
  const fn = load().resolveRenderer({ name: 'deviceName' }, URLS, {});
  assert.strictEqual(fn(null, 'display', { ip: '10.0.0.1', name: 'sw1' }), 'sw1');
});

// A caller whose dns/name/ip keys would themselves collide with something
// else read from the same spec nests them under "label" instead, the shape
// searchDeviceLink already uses.
test('renderers__deviceName__label__nests_dns_name_ip_to_avoid_the_dispatch_key', () => {
  const fn = load().resolveRenderer({ name: 'deviceName', label: { dns: 'device.dns', name: 'device.name', ip: 'ip' } }, URLS, {});
  assert.strictEqual(fn(null, 'display', { ip: '10.0.0.1', device: { dns: '', name: 'sw1' } }), 'sw1');
});

// The closure each of these renderers replaces read a fixed, different
// subset of dns/name/ip; naming a subset here must not fall through to a
// tier the caller never asked for, even when the row carries one.
test('renderers__deviceName__naming_a_subset__consults_only_the_named_tiers', () => {
  const r = load().renderers.deviceName({ name: 'name', ip: 'ip' }, URLS);
  assert.strictEqual(r(null, 'display', { dns: 'sw1.example', name: 'sw1', ip: '10.0.0.1' }), 'sw1');
});

test('renderers__deviceName__naming_none__keeps_the_full_dns_name_ip_fallback', () => {
  const r = load().renderers.deviceName({}, URLS);
  assert.strictEqual(r(null, 'display', { dns: 'sw1.example', name: 'sw1', ip: '10.0.0.1' }), 'sw1.example');
});

test('renderers__age__shows_the_text_and_sorts_by_the_stamp', () => {
  const r = load().renderers.age({ stamp: 'time_last' }, URLS);
  assert.strictEqual(r('2:30:00', 'display', { time_last: '2026-09-04' }), '2 hours 30 mins');
  assert.strictEqual(r('2:30:00', 'sort', { time_last: '2026-09-04' }), '2026-09-04');
  assert.strictEqual(r(null, 'display', {}), 'Never');
});

test('resolveRenderer__a_string__is_a_renderer_with_no_args', () => {
  const t = load();
  const r = t.resolveRenderer('escape', URLS, {});
  assert.strictEqual(r('x', 'display', {}), 'x');
});

test('resolveRenderer__an_unknown_name__throws_naming_it', () => {
  const t = load();
  assert.throws(() => t.resolveRenderer('nope', URLS, {}), /nope/);
});

// A callback named where a column wants a renderer (or the reverse) is a
// fragment author's mistake in which JSON key it went under; naming the
// mistake in the error is the whole point of keeping two registries.
test('resolveRenderer__a_callback_name__throws_naming_it_as_a_callback', () => {
  const t = load();
  assert.throws(() => t.resolveRenderer('portsCollapse', URLS, {}), /"portsCollapse" is a callback, not a renderer/);
});

test('resolveCallback__a_renderer_name__throws_naming_it_as_a_renderer', () => {
  const t = load();
  assert.throws(() => t.resolveCallback('escape', URLS, {}), /"escape" is a renderer, not a callback/);
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

// htmx swaps one tab pane at a time and never empties the pane it leaves,
// so document.getElementById can answer with a stale sibling pane's block.
// document is rigged here to always return the wrong one, standing in for
// that hazard; build(table, root) must still get each table's own rows by
// looking inside its own just-swapped root first.
test('build__with_a_root__resolves_each_tables_data_block_inside_that_root', () => {
  const built = [];
  const t = load({ built });
  const block1 = { textContent: '[{"ip":"10.0.0.1"}]' };
  const block2 = { textContent: '[{"vlan":10}]' };
  const document = { getElementById: () => block1 };
  const root1 = { querySelector: (sel) => (sel === '#nd-results-1' ? block1 : null) };
  const root2 = { querySelector: (sel) => (sel === '#nd-results-2' ? block2 : null) };
  const table1 = { dataset: { ndTable: '{"columns":[{"data":"ip","render":"escape"}]}', ndUrls: '{}', ndData: '#nd-results-1' }, ownerDocument: document };
  const table2 = { dataset: { ndTable: '{"columns":[{"data":"vlan","render":"raw"}]}', ndUrls: '{}', ndData: '#nd-results-2' }, ownerDocument: document };
  t.build(table1, root1);
  t.build(table2, root2);
  assert.deepStrictEqual(built[0].config.data, [{ ip: '10.0.0.1' }]);
  assert.deepStrictEqual(built[1].config.data, [{ vlan: 10 }]);
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
//
// Each data-nd-table value is parsed as JSON rather than scanned with a
// regex: a regex has no notion of which "name" key belongs to the render
// spec itself and which to something nested inside it (searchDeviceLink's
// "label" argument is itself keyed dns/name/ip), so it can be led to the
// wrong one depending only on which key happens to be written first.
test('fragments__every_render_and_callback_name__is_in_the_registry', () => {
  const t = load();
  const VIEWS = path.join(ROOT, 'share', 'views', 'ajax');
  const names = new Set();

  function collectSpecName(spec) {
    if (typeof spec === 'string') names.add(spec);
    else if (spec && typeof spec === 'object' && typeof spec.name === 'string') names.add(spec.name);
  }

  const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).forEach((e) => {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) return walk(full);
    const text = fs.readFileSync(full, 'utf8');
    for (const value of attributeValues(text, 'data-nd-table')) {
      var spec;
      try { spec = JSON.parse(stripDirectives(value)) }
      catch (err) { throw new Error(full + ': data-nd-table does not parse as JSON: ' + err.message) }
      (spec.columns || []).forEach((col) => { if (col.render) collectSpecName(col.render) });
      (spec.columnDefs || []).forEach((def) => { if (def.render) collectSpecName(def.render) });
      if (spec.drawCallback) collectSpecName(spec.drawCallback);
      if (spec.initComplete) collectSpecName(spec.initComplete);
    }
  });
  walk(VIEWS);
  const missing = [...names].filter((n) => !(n in t.renderers) && !(n in t.callbacks));
  assert.deepStrictEqual(missing, []);
});

// A renderer that needs a URL throws at resolve time naming the missing
// data-nd-urls key, but only if the fragment is exercised: this drives every
// fragment's own render, drawCallback and initComplete specs through the
// registry with the fragment's own data-nd-urls, so a fragment that forgot a
// key fails here rather than when a viewer opens the tab. Run twice, once per
// data-nd-admin value, because subnetLink only requires "uri_base" for an
// admin viewer.
//
// <table ...> is matched as one block, pairing each data-nd-urls with the
// data-nd-table beside it, because four fragments carry two tables and a
// bare pair of attribute regexes run separately over the whole file would
// pair the first table's urls with the second table's spec.
test('fragments__every_table__supplies_the_url_keys_its_renderers_need', () => {
  const t = load();
  const VIEWS = path.join(ROOT, 'share', 'views', 'ajax');
  const tables = [];

  const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).forEach((e) => {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) return walk(full);
    const text = fs.readFileSync(full, 'utf8');
    for (const m of text.matchAll(/<table\b[\s\S]*?>/g)) {
      const block = stripDirectives(m[0]);
      const tableValues = attributeValues(block, 'data-nd-table');
      if (!tableValues.length) continue;
      const tableMatch = [null, tableValues[0]];
      const urlValues = attributeValues(block, 'data-nd-urls');
      const urlsMatch = urlValues.length ? [null, urlValues[0]] : null;
      var spec, urls;
      try { spec = JSON.parse(tableMatch[1]) }
      catch (err) { throw new Error(full + ': data-nd-table does not parse as JSON: ' + err.message) }
      try { urls = urlsMatch ? JSON.parse(urlsMatch[1]) : {} }
      catch (err) { throw new Error(full + ': data-nd-urls does not parse as JSON: ' + err.message) }
      const specs = [];
      (spec.columns || []).forEach((col) => { if (col.render) specs.push({ spec: col.render, kind: 'renderer' }) });
      (spec.columnDefs || []).forEach((def) => { if (def.render) specs.push({ spec: def.render, kind: 'renderer' }) });
      if (spec.drawCallback) specs.push({ spec: spec.drawCallback, kind: 'callback' });
      if (spec.initComplete) specs.push({ spec: spec.initComplete, kind: 'callback' });
      tables.push({ file: full, urls: urls, specs: specs });
    }
  });
  walk(VIEWS);
  assert.ok(tables.length > 0, 'the scan found at least one table');

  ['0', '1'].forEach((ndAdmin) => {
    tables.forEach(({ file, urls, specs }) => {
      specs.forEach(({ spec, kind }) => {
        const table = { dataset: { ndAdmin: ndAdmin } };
        const resolveFn = (kind === 'renderer') ? t.resolveRenderer : t.resolveCallback;
        try {
          resolveFn(spec, urls, table);
        } catch (err) {
          assert.fail(file + ' (data-nd-admin=' + ndAdmin + '): ' + err.message);
        }
      });
    });
  });
});
