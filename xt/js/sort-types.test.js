// Coverage for the three sort plug-ins that had no test at all:
// versionsort.js, dataTables.ip-address-sort.js and
// dataTables.ip-address-detect.js. portsort.js has its own suite.
//
// A sort plug-in fails silently. A type nothing registers is not an error the
// library reports: it compares the cell text instead, so 10.0.0.10 sorts before
// 10.0.0.9 and every page still renders. The address plug-ins are quieter
// again, because no template names their type and the library reaches them only
// by detecting a dotted quad, so there is nothing in the markup to notice.
//
// Whether the library actually consults any of this is a browser question and
// is answered by the Playwright harness. These checks only stop the
// registration going away, or the two address files drifting apart.

'use strict';

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const JS_DIR = path.join(__dirname, '..', '..', 'share', 'public', 'javascripts');

// DataTable.type writes only the keys the spec carries, which is what lets the
// detect file and the sort file register the same type from two files. A stub
// that replaced the whole entry would hide a real registration losing half of
// itself.
globalThis.DataTable = {
  registered: {},
  type(name, spec) {
    const entry = this.registered[name] || (this.registered[name] = {});
    for (const key of Object.keys(spec)) entry[key] = spec[key];
  },
};

for (const file of ['versionsort.js', 'dataTables.ip-address-sort.js',
                    'dataTables.ip-address-detect.js']) {
  require(path.join(JS_DIR, file));
}

const registered = globalThis.DataTable.registered;

describe('registration', () => {
  test('sortPlugins__loaded_against_a_library_stub__register_the_two_types_and_no_others', () => {
    assert.deepStrictEqual(Object.keys(registered).sort(), ['ip-address', 'versionsort']);
  });

  test('versionSort__loaded_against_a_library_stub__registers_a_key_and_both_directions', () => {
    assert.deepStrictEqual(Object.keys(registered.versionsort.order).sort(),
      ['asc', 'desc', 'pre']);
  });

  test('ipAddressSort__loaded_against_a_library_stub__registers_a_key_and_both_directions', () => {
    assert.deepStrictEqual(Object.keys(registered['ip-address'].order).sort(),
      ['asc', 'desc', 'pre']);
  });

  // The detection function is the only route to the address type, so its name
  // and the name the order is registered under have to be one string. They are
  // written in two files, which is where they can drift.
  test('ipAddressDetect__a_dotted_quad__answers_with_the_name_the_order_is_registered_under', () => {
    assert.equal(registered['ip-address'].detect('192.168.0.1'), 'ip-address');
    assert.ok(registered['ip-address'].order,
      'the detected name has an order registered against it');
  });

  test('ipAddressDetect__anything_that_is_not_a_dotted_quad__answers_false', () => {
    for (const notAnAddress of ['GigabitEthernet1/1', '192.168.0', '1.2.3.4.5',
                                'v1.2.3.4', '', 'Vlan10']) {
      assert.equal(registered['ip-address'].detect(notAnAddress), false,
        notAnAddress + ' is not an address');
    }
  });
});

describe('ordering', () => {
  function assertOrders(type, unordered, expected) {
    const { pre, asc, desc } = registered[type].order;
    const keyed = unordered.map(pre);
    assert.deepStrictEqual(keyed.slice().sort(asc), expected.map(pre));
    assert.deepStrictEqual(keyed.slice().sort(desc), expected.slice().reverse().map(pre));
  }

  test('versionSort__release_numbers_of_mixed_width__orders_by_value_not_by_text', () => {
    assertOrders('versionsort',
      ['12.2(55)SE', '9.10', '12.2(9)SE', '10.2', '9.9'],
      ['9.9', '9.10', '10.2', '12.2(9)SE', '12.2(55)SE']);
  });

  test('versionSort__a_letter_suffix__orders_after_the_bare_release', () => {
    assertOrders('versionsort', ['15.0a', '15.0', '15.0b'], ['15.0', '15.0a', '15.0b']);
  });

  test('ipAddressSort__addresses_in_one_subnet__orders_the_last_octet_numerically', () => {
    assertOrders('ip-address',
      ['10.0.0.10', '10.0.0.9', '10.0.0.2'],
      ['10.0.0.2', '10.0.0.9', '10.0.0.10']);
  });

  test('ipAddressSort__addresses_across_subnets__orders_every_octet_numerically', () => {
    assertOrders('ip-address',
      ['192.168.10.1', '10.0.0.1', '192.168.2.1', '99.1.1.1'],
      ['10.0.0.1', '99.1.1.1', '192.168.2.1', '192.168.10.1']);
  });
});

// The registration moved off jQuery ahead of the library upgrade, so that the
// upgrade and the removal of jQuery are two changes rather than one. A file
// reaching back for the old API compiles and registers nothing once jQuery is
// gone, which is the silent failure above.
describe('no jQuery', () => {
  for (const file of ['portsort.js', 'versionsort.js', 'dataTables.ip-address-sort.js',
                      'dataTables.ip-address-detect.js']) {
    test('sortPlugin__' + file.replace(/\W/g, '_') + '__names_jquery_nowhere', () => {
      const source = fs.readFileSync(path.join(JS_DIR, file), 'utf8');
      for (const banned of ['jQuery', 'dataTableExt', '$(']) {
        assert.ok(!source.includes(banned),
          file + ' still names ' + banned + '; register with DataTable.type instead');
      }
    });
  }
});
