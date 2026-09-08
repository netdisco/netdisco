// The routes these helpers reach are declared with Dancer's ajax keyword,
// which skips the route entirely without the XMLHttpRequest header. fetch
// sends nothing on its own, so the assertion below is what stands between a
// call through this helper and a button that answers 404.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const SRC = path.join(__dirname, '..', '..', 'share', 'public', 'javascripts',
  'netdisco-request.js');

function load(fetchStub) {
  const window = { location: { origin: 'http://example.net' } };
  const context = {
    window,
    document: { querySelectorAll: () => [] },
    fetch: fetchStub,
    URLSearchParams,
    console,
  };
  context.globalThis = context;
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(SRC, 'utf8'), context);
  return window.ndRequest;
}

test('post__sending_a_body__carries_the_XMLHttpRequest_header', async () => {
  let seen = null;
  const ndRequest = load((url, init) => { seen = { url, init }; return Promise.resolve({ ok: true, status: 200 }); });
  await ndRequest.post('/ajax/portcontrol', new URLSearchParams({ device: '192.0.2.1' }));
  assert.equal(seen.url, '/ajax/portcontrol');
  assert.equal(seen.init.method, 'POST');
  assert.equal(seen.init.headers['X-Requested-With'], 'XMLHttpRequest');
  assert.match(seen.init.headers['Content-Type'], /application\/x-www-form-urlencoded/);
  assert.equal(seen.init.credentials, 'same-origin');
  assert.equal(String(seen.init.body), 'device=192.0.2.1');
});

test('post__a_server_error__resolves_so_the_caller_can_read_the_status', async () => {
  const ndRequest = load(() => Promise.resolve({ ok: false, status: 500 }));
  const res = await ndRequest.post('/ajax/portcontrol', new URLSearchParams());
  assert.equal(res.status, 500, 'fetch does not reject on 5xx and the helper must not hide that');
});

test('fields__over_a_row_of_inputs__skips_an_unchecked_box_and_a_nameless_field', () => {
  const ndRequest = load(() => Promise.resolve({ ok: true }));
  const row = {
    querySelectorAll: () => ([
      { name: 'port', value: 'Gi0/1', type: 'text' },
      { name: 'up', value: 'on', type: 'checkbox', checked: false },
      { name: 'down', value: 'on', type: 'checkbox', checked: true },
      { name: '', value: 'ignored', type: 'text' },
    ]),
  };
  assert.equal(String(ndRequest.fields(row, 'input')), 'port=Gi0%2F1&down=on');
});

test('fields__a_multiple_select_with_two_chosen_options__contributes_one_pair_per_option', () => {
  const ndRequest = load(() => Promise.resolve({ ok: true }));
  const row = {
    querySelectorAll: () => ([
      {
        name: 'vendor',
        type: 'select-multiple',
        selectedOptions: [{ value: 'cisco' }, { value: 'juniper' }],
      },
    ]),
  };
  assert.equal(String(ndRequest.fields(row, 'select')), 'vendor=cisco&vendor=juniper');
});

test('fields__a_disabled_field__contributes_nothing_while_its_neighbor_does', () => {
  const ndRequest = load(() => Promise.resolve({ ok: true }));
  const row = {
    querySelectorAll: () => ([
      { name: 'token_acl', value: 'stale', type: 'select-one', disabled: true },
      { name: 'other', value: 'ok', type: 'text', disabled: false },
    ]),
  };
  assert.equal(String(ndRequest.fields(row, 'select, input')), 'other=ok');
});

test('fields__a_value_with_a_bare_newline__serializes_with_crlf', () => {
  const ndRequest = load(() => Promise.resolve({ ok: true }));
  const row = {
    querySelectorAll: () => ([
      { name: 'note', value: 'line1\nline2', type: 'textarea' },
    ]),
  };
  assert.equal(String(ndRequest.fields(row, 'textarea')), 'note=line1%0D%0Aline2');
});

test('query__over_a_form__matches_the_query_string_the_server_expects', () => {
  const ndRequest = load(() => Promise.resolve({ ok: true }));
  const form = {
    querySelectorAll: () => ([
      { name: 'q', value: '192.0.2.1', type: 'text' },
      { name: 'age', value: '1 day', type: 'text' },
    ]),
  };
  assert.equal(ndRequest.query(form), 'q=192.0.2.1&age=1+day');
});
