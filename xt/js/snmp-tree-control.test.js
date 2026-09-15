// The SNMP tree's open/close control against the level lines it sits on.
//
// SOURCE ASSERTION. Which element wins a hit test is a browser question, and
// the harness spec interact-snmp-tree.spec.js asks it there.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const css = fs.readFileSync(
  path.join(__dirname, '..', '..', 'share', 'public', 'css', 'netdisco.css'), 'utf8');

const rule = (selector) => {
  const found = css.match(new RegExp(selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\s*\\{[^}]*\\}'));
  assert.ok(found, `netdisco.css must carry a ${selector} rule`);
  return found[0];
};

test('snmpTreeControl__sitting_on_the_level_lines__is_stacked_above_them', () => {
  assert.match(rule('.nd_snmp-row > details > summary'), /z-index:\s*[1-9]/,
    'the ::after tick follows this control in tree order, so without a stacking '
    + 'position it paints across the box and takes the click at its center');
});

// If the tick were moved clear of the box instead, the test above would be
// guarding nothing.
test('snmpTreeControl__and_the_rows_tick__still_occupy_the_same_place', () => {
  const control = rule('.nd_snmp-row > details > summary');
  const tick = rule('.nd_snmp-row::after');
  const px = (text, prop) => {
    const m = text.match(new RegExp(prop + ':\\s*(-?\\d+)px'));
    return m ? Number(m[1]) : null;
  };
  const controlLeft = px(control, 'left');
  const tickLeft = px(tick, 'left');
  const tickWidth = px(tick, 'width');
  assert.ok(controlLeft !== null && tickLeft !== null && tickWidth !== null,
    'the control and the tick are no longer placed in pixels; re-read this rule');
  assert.ok(tickLeft < controlLeft + 13 && tickLeft + tickWidth > controlLeft,
    'the tick no longer crosses the control, so replace both tests here with '
    + 'whatever now keeps them apart');
});
