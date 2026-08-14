// Coverage for share/public/javascripts/portsort.js, which registers the
// "portsort" sort type used by the device Ports tab and several reports.
//
// The cases are ported from xt/html/portsort.html, the QUnit page removed in
// 9b8fbcb7. Read the original out of git history at
// acb77e37:xt/html/portsort.html before adding cases, rather than inventing
// them: it is the specification.

'use strict';

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

// portsort.js takes jQuery from global scope and registers its comparators as a
// side effect of being loaded, so the stub has to exist before the require.
globalThis.jQuery = {
  extend: Object.assign,
  fn: { dataTableExt: { oSort: {} } },
};

require(path.join(__dirname, '..', '..', 'share', 'public', 'javascripts', 'portsort.js'));

const sortTypes = globalThis.jQuery.fn.dataTableExt.oSort;

function assertSortsTo(unordered, expected, because) {
  assert.deepStrictEqual(unordered.slice().sort(sortTypes['portsort-asc']), expected, because);
}

describe('registration', () => {
  test('portSort__loaded_against_a_jquery_stub__registers_both_directions', () => {
    assert.deepStrictEqual(Object.keys(sortTypes).sort(), ['portsort-asc', 'portsort-desc']);
  });

  test('portSortDescending__interface_names__reverses_the_ascending_order', () => {
    const names = ['GigabitEthernet1/2', 'GigabitEthernet1/10', 'GigabitEthernet1/1'];
    assert.deepStrictEqual(
      names.slice().sort(sortTypes['portsort-desc']),
      names.slice().sort(sortTypes['portsort-asc']).reverse());
  });
});

describe('different value types', () => {
  test('portSort__a_number_and_a_string__puts_the_number_first', () => {
    assertSortsTo(['a', 1], [1, 'a']);
  });

  test('portSort__a_number_and_its_numeric_string__leaves_the_order_alone', () => {
    assertSortsTo(['1', 1], ['1', 1]);
  });

  test('portSort__zero_padded_numeric_strings_and_numbers__puts_the_padded_strings_first', () => {
    assertSortsTo(['02', 3, 2, '01'], ['01', '02', 2, 3]);
  });
});

describe('numerics', () => {
  test('portSort__numeric_strings_and_numbers__orders_by_value_not_by_type', () => {
    assertSortsTo(['10', 9, 2, '1', '4'], ['1', 2, '4', 9, '10']);
  });

  test('portSort__zero_left_padded_numbers__orders_by_the_padding_then_the_digits', () => {
    assertSortsTo(['0001', '002', '001'], ['0001', '001', '002']);
  });

  test('portSort__zero_left_padded_and_bare_numbers__puts_every_padded_form_first', () => {
    assertSortsTo([2, 1, '1', '0001', '002', '02', '001'], ['0001', '001', '002', '02', 1, '1', 2]);
  });

  test('portSort__decimals_of_different_precision__orders_by_value', () => {
    assertSortsTo(['10.0401', 10.022, 10.042, '10.021999'], ['10.021999', 10.022, '10.0401', 10.042]);
  });

  test('portSort__decimals_of_the_same_precision__orders_by_value', () => {
    assertSortsTo(['10.04', 10.02, 10.03, '10.01'], ['10.01', 10.02, 10.03, '10.04']);
  });

  test('portSort__numbers_of_mixed_length__orders_numerically_not_lexically', () => {
    assertSortsTo(
      ['10001', '10011', '101', '10010', '10', '100', '10002', '10112', '10111'],
      ['10', '100', '101', '10001', '10002', '10010', '10011', '10111', '10112']);
  });
});

describe('IP addresses', () => {
  test('portSort__ip_addresses__orders_each_octet_numerically', () => {
    assertSortsTo(
      ['192.168.0.100', '192.168.0.1', '192.168.1.1', '192.168.0.250',
       '192.168.1.123', '10.0.0.2', '10.0.0.1'],
      ['10.0.0.1', '10.0.0.2', '192.168.0.1', '192.168.0.100',
       '192.168.0.250', '192.168.1.1', '192.168.1.123']);
  });
});

describe('leading whitespace', () => {
  test('portSort__values_with_leading_spaces__ignores_the_spaces', () => {
    assertSortsTo(['alpha', ' 1', '  3', ' 2', 0], [0, ' 1', ' 2', '  3', 'alpha']);
  });
});

describe('wireless controllers', () => {
  test('portSort__access_point_ports__orders_by_mac_then_radio', () => {
    assertSortsTo(
      ['00:14:0e:12:34:56', '00:08:30:01:23:45.1', '00:15:c7:ab:23:10.0',
       '00:14:0e:01:23:45', '00:08:30:01:23:45.0', '00:15:c7:ab:23:00.1'],
      ['00:08:30:01:23:45.0', '00:08:30:01:23:45.1', '00:14:0e:01:23:45',
       '00:14:0e:12:34:56', '00:15:c7:ab:23:00.1', '00:15:c7:ab:23:10.0']);
  });

  test('portSort__controller_ports__orders_the_bare_port_before_its_subinterfaces', () => {
    assertSortsTo(
      ['wlan-controller1/0.104', 'wlan-controller1/0', 'wlan-controller1/0.252',
       'wlan-controller1/0.103'],
      ['wlan-controller1/0', 'wlan-controller1/0.103', 'wlan-controller1/0.104',
       'wlan-controller1/0.252']);
  });
});

describe('interface names by vendor', () => {
  test('portSort__avaya_port_names__orders_by_slot_then_port', () => {
    assertSortsTo(
      ['1.1', '1.13', '1.14', '1.19', '1.2', 'Vlan318', '1.25', '1.29',
       '3.12', '1.3', '1.37', '1.38', '1.4', '1.43', '1.6', '8.34'],
      ['1.1', '1.2', '1.3', '1.4', '1.6', '1.13', '1.14', '1.19', '1.25',
       '1.29', '1.37', '1.38', '1.43', '3.12', '8.34', 'Vlan318']);
  });

  test('portSort__cisco_interface_names__orders_by_each_slash_separated_number', () => {
    assertSortsTo(
      ['GigabitEthernet9/0/12', 'GigabitEthernet9/0/11',
       'GigabitEthernet1/0/14', 'GigabitEthernet1/1/12'],
      ['GigabitEthernet1/0/14', 'GigabitEthernet1/1/12',
       'GigabitEthernet9/0/11', 'GigabitEthernet9/0/12']);
  });

  test('portSort__dell_port_names__orders_by_each_slash_separated_number', () => {
    assertSortsTo(
      ['1/1/1', '0/1/1', '0/3/20', '0/2/1', '0/3/1', '0/3/2', '0/3/11', '0/3/10'],
      ['0/1/1', '0/2/1', '0/3/1', '0/3/2', '0/3/10', '0/3/11', '0/3/20', '1/1/1']);
  });

  test('portSort__extreme_port_names__orders_by_the_number_after_the_colon', () => {
    assertSortsTo(['1:10', '1:2', '1:1', '1:11'], ['1:1', '1:2', '1:10', '1:11']);
  });

  test('portSort__hp_a_and_d_port_names__orders_by_letter_then_number', () => {
    assertSortsTo(['D10', 'D11', 'D2', 'D1', 'A30', 'A3'], ['A3', 'A30', 'D1', 'D2', 'D10', 'D11']);
  });

  test('portSort__hp_a_and_b_port_names__orders_by_letter_then_number', () => {
    assertSortsTo(['B10', 'B11', 'B2', 'B1', 'A30', 'A3'], ['A3', 'A30', 'B1', 'B2', 'B10', 'B11']);
  });

  // The expected order interleaves the two prefixes because portSort rewrites a
  // leading "10GigabitEthernet" to "GigabitEthernet" before comparing, so
  // foundry names sort alongside the cisco-style ones they are equivalent to.
  test('portSort__foundry_ten_gigabit_names__sorts_them_as_their_cisco_equivalents', () => {
    assertSortsTo(
      ['10GigabitEthernet1/1/12', 'GigabitEthernet1/0/14',
       'GigabitEthernet9/0/12', '10GigabitEthernet9/0/11'],
      ['GigabitEthernet1/0/14', '10GigabitEthernet1/1/12',
       '10GigabitEthernet9/0/11', 'GigabitEthernet9/0/12']);
  });

  test('portSort__netgear_port_descriptions__orders_by_slot_then_port', () => {
    assertSortsTo(
      ['Slot: 1 Port: 2 Gigabit - Level', 'Slot: 1 Port: 1 Gigabit - Level',
       'Slot: 0 Port: 15 Gigabit - Level', 'Slot: 1 Port: 10 Gigabit - Level',
       'Slot: 0 Port: 1 Gigabit - Level'],
      ['Slot: 0 Port: 1 Gigabit - Level', 'Slot: 0 Port: 15 Gigabit - Level',
       'Slot: 1 Port: 1 Gigabit - Level', 'Slot: 1 Port: 2 Gigabit - Level',
       'Slot: 1 Port: 10 Gigabit - Level']);
  });

  test('portSort__port_channel_names__orders_by_the_trailing_number', () => {
    assertSortsTo(
      ['port-channel190', 'port-channel19', 'port-channel1044', 'port-channel2',
       'port-channel104'],
      ['port-channel2', 'port-channel19', 'port-channel104', 'port-channel190',
       'port-channel1044']);
  });

  test('portSort__serial_channel_names__orders_a_channel_before_its_bearer', () => {
    assertSortsTo(
      ['Serial1/1:5', 'Serial2/0:5-Bearer Channel', 'Serial2/0:20',
       'Serial1/1:5-Bearer Channel', 'Serial1/1:0', 'Serial2/0:21',
       'Serial2/0:5', 'Serial2/0:20-Bearer Channel'],
      ['Serial1/1:0', 'Serial1/1:5', 'Serial1/1:5-Bearer Channel',
       'Serial2/0:5', 'Serial2/0:5-Bearer Channel', 'Serial2/0:20',
       'Serial2/0:20-Bearer Channel', 'Serial2/0:21']);
  });

  test('portSort__unrouted_vlan_names__orders_by_the_trailing_number', () => {
    assertSortsTo(
      ['unrouted VLAN 990', 'unrouted VLAN 95', 'unrouted VLAN 985',
       'unrouted VLAN 99', 'unrouted VLAN 950'],
      ['unrouted VLAN 95', 'unrouted VLAN 99', 'unrouted VLAN 950',
       'unrouted VLAN 985', 'unrouted VLAN 990']);
  });

  test('portSort__vlan_names__orders_by_the_trailing_number', () => {
    assertSortsTo(['Vlan10', 'Vlan910', 'Vlan1', 'Vlan91'], ['Vlan1', 'Vlan10', 'Vlan91', 'Vlan910']);
  });

  test('portSort__voice_port_names__orders_by_the_number_after_the_slash', () => {
    assertSortsTo(
      ['voice-port 2/10', 'voice-port 2/1', 'voice-port 2/2', 'voice-port 2/11'],
      ['voice-port 2/1', 'voice-port 2/2', 'voice-port 2/10', 'voice-port 2/11']);
  });
});

// The same list of ports is ordered twice by two separate implementations:
// sort_port in App::Netdisco::Util::Web orders the rows before the page is
// rendered (Ports.pm:295), and portSort reorders those same rows when the user
// clicks the column heading (ports.tt:616 registers it as the DataTables sort
// type). If they disagree, the order changes under the user for no visible
// reason.
//
// These cases are xt/10-sort_port.t's, expectations included, so a change here
// that breaks agreement with the Perl side fails. Keep the two lists in step.
describe('agreement with the Perl sort_port', () => {
  function assertAgreesWithSortPort(first, second, expected) {
    assert.equal(Math.sign(sortTypes['portsort-asc'](first, second)), expected,
      `${first} against ${second}`);
  }

  test('portSort__identical_values__agrees_that_neither_is_greater', () => {
    assertAgreesWithSortPort(1, 1, 0);
  });

  test('portSort__extreme_colon_ports__agrees_with_sort_port', () => {
    assertAgreesWithSortPort('1:2', '1:10', -1);
  });

  test('portSort__hp_letter_then_number_ports__agrees_with_sort_port', () => {
    assertAgreesWithSortPort('D1', 'D10', -1);
  });

  test('portSort__juniper_oc3_pic_interfaces__agrees_with_sort_port', () => {
    assertAgreesWithSortPort('so-1/0/0.0', 'so-1/0/1.0', -1);
    assertAgreesWithSortPort('so-1/1/0.0', 'so-1/1/1.0', -1);
    assertAgreesWithSortPort('so-1/0/0.0', 'so-1/1/0.0', -1);
  });

  test('portSort__juniper_channelized_interfaces__agrees_with_sort_port', () => {
    assertAgreesWithSortPort('so-1/0/0:0', 'so-1/0/1:0', -1);
    assertAgreesWithSortPort('so-1/1/0:0', 'so-1/1/1:0', -1);
    assertAgreesWithSortPort('so-1/0/0:0', 'so-1/1/0:0', -1);
  });
});
