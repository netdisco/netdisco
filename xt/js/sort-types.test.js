// A sort plug-in fails silently: a type nothing registers is not an error the
// library reports, it compares the cell text instead and every page still
// renders. No template names the address type either, so the library reaches
// it only by detecting a dotted quad.
//
// Whether the library consults any of this is a browser question, answered by
// the Playwright harness.

'use strict';

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const JS_DIR = path.join(__dirname, '..', '..', 'share', 'public', 'javascripts');

// Merges rather than replaces, because the detect file and the sort file
// register the same type from two files.
globalThis.DataTable = {
  registered: {},
  type(name, spec) {
    const entry = this.registered[name] || (this.registered[name] = {});
    for (const key of Object.keys(spec)) entry[key] = spec[key];
  },
  // Mirrors dataTables.min.js: one sweep of the tag pattern, then a fixpoint
  // on the literal "<script", which one sweep cannot do because a removal can
  // splice two halves of it together. Kept in step by hand.
  util: {
    stripHtml(value) {
      let out = String(value).replace(/<([^>]*>)/g, '');
      let previous;
      do { previous = out; out = out.replace(/<script/i, ''); } while (out !== previous);
      return out;
    },
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

  // Detection is the only route to the type, so the name it answers with and
  // the name the order registers under are one string written in two files.
  test('ipAddressDetect__a_dotted_quad__answers_with_the_name_the_order_is_registered_under', () => {
    assert.equal(registered['ip-address'].detect('192.168.0.1'), 'ip-address');
    assert.ok(registered['ip-address'].order,
      'the detected name has an order registered against it');
  });

  // netdisco links most of the addresses it prints, so the cell is markup.
  test('ipAddressDetect__an_address_the_page_has_linked__is_still_an_address', () => {
    assert.equal(registered['ip-address'].detect(
      '<a class="nd_linkcell" href="/device?tab=details&q=10.0.0.9">10.0.0.9</a>'),
      'ip-address');
  });

  // An unterminated tag never matches <([^>]*>), so a single sweep leaves it
  // in the text. Not markup the product emits, but the case a sweep cannot
  // reach.
  test('ipAddressDetect__an_address_followed_by_an_unterminated_tag__is_still_an_address', () => {
    assert.equal(registered['ip-address'].detect('10.0.0.9<script'), 'ip-address');
  });

  test('ipAddressDetect__anything_that_is_not_a_dotted_quad__answers_false', () => {
    for (const notAnAddress of ['GigabitEthernet1/1', '192.168.0', '1.2.3.4.5',
                                'v1.2.3.4', '', 'Vlan10',
                                // anything beside the address and it cannot
                                // be keyed on, so it must not be claimed
                                '<a href="/x">10.0.0.9</a> switch-a',
                                'see 10.0.0.9']) {
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

  // The href holds dots of its own, so keying the raw cell keys on the URL.
  test('ipAddressSort__linked_addresses__order_by_the_address_and_not_the_href', () => {
    const link = (ip) => '<a class="nd_linkcell" href="/device?tab=details&q=' + ip + '">' + ip + '</a>';
    assertOrders('ip-address',
      [link('10.0.0.10'), link('10.0.0.9'), link('10.0.0.2')],
      [link('10.0.0.2'), link('10.0.0.9'), link('10.0.0.10')]);
  });

  test('ipAddressSort__addresses_across_subnets__orders_every_octet_numerically', () => {
    assertOrders('ip-address',
      ['192.168.10.1', '10.0.0.1', '192.168.2.1', '99.1.1.1'],
      ['10.0.0.1', '99.1.1.1', '192.168.2.1', '192.168.10.1']);
  });
});

// A file reaching back for the old jQuery API compiles and registers nothing,
// which is the silent failure above.
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
