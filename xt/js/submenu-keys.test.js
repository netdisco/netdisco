// Guards arrow-key movement inside the navbar's dropend submenus.
//
// Bootstrap resolves the toggle for a keyboard event by looking beside the
// menu the event came from. A dropend submenu's category link carries the
// dropdown-toggle class but not the data-bs-toggle attribute, so that lookup
// finds nothing, and Bootstrap builds a Dropdown from undefined and throws.
// netdisco.js takes Escape and both arrows before Bootstrap sees them, which
// means it owns the movement and this file checks the arithmetic of it.
//
// The index arithmetic below is exercised for real; that the listener is wired
// to the arrows at all is a source assertion, and whether a keypress moves
// focus in a browser is checked by the Playwright harness.

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const source = fs.readFileSync(
  path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco.js'), 'utf8');

function extract(name) {
  const from = source.indexOf('function ' + name);
  if (from < 0) throw new Error('no function ' + name + ' in netdisco.js');
  let depth = 0;
  for (let j = source.indexOf('{', from); j < source.length; j += 1) {
    if (source[j] === '{') depth += 1;
    if (source[j] === '}') { depth -= 1; if (depth === 0) return source.slice(from, j + 1); }
  }
  throw new Error('unbalanced braces in ' + name);
}

const focusIndex = new Function(
  extract('nd_submenu_focus_index') + '; return nd_submenu_focus_index;')();

test('submenuFocusIndex__arrowing_down_mid_list__takes_the_next_item', () => {
  assert.equal(focusIndex(5, 0, 'ArrowDown'), 1);
  assert.equal(focusIndex(5, 3, 'ArrowDown'), 4);
});

test('submenuFocusIndex__arrowing_up_mid_list__takes_the_previous_item', () => {
  assert.equal(focusIndex(5, 4, 'ArrowUp'), 3);
  assert.equal(focusIndex(5, 1, 'ArrowUp'), 0);
});

// Bootstrap stops at the ends of the top-level menu rather than cycling round.
test('submenuFocusIndex__arrowing_down_at_the_last_item__stays_put', () => {
  assert.equal(focusIndex(5, 4, 'ArrowDown'), 4);
  assert.equal(focusIndex(1, 0, 'ArrowDown'), 0);
});

// -1 is the caller's signal to focus the category that opened the submenu.
test('submenuFocusIndex__arrowing_up_at_the_first_item__leaves_for_the_category', () => {
  assert.equal(focusIndex(5, 0, 'ArrowUp'), -1);
});

test('submenuFocusIndex__with_focus_on_the_submenu_itself__enters_at_the_first_item', () => {
  assert.equal(focusIndex(5, -1, 'ArrowDown'), 0);
  assert.equal(focusIndex(5, -1, 'ArrowUp'), -1);
});

// Sliced from the arrow filter rather than from the top of the listener: the
// Escape branch above it stops propagation too, and matching that instead
// would pass with the arrows left unguarded.
test('netdiscoJs__before_bootstrap_can_throw__takes_both_arrows_in_the_submenu', () => {
  const from = source.indexOf("if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown')");
  assert.ok(from > 0,
    'the submenu keydown listener no longer filters on both arrow keys, so'
    + " Bootstrap's own handler sees them and throws on the nested menu");
  const arrows = source.slice(from, source.indexOf('}, true);', from));
  assert.ok(/event\.stopPropagation\(\)/.test(arrows),
    'the arrow branch of the submenu keydown listener no longer stops'
    + ' propagation, so Bootstrap still receives the key and throws');
  assert.ok(/nd_submenu_focus_index\(/.test(arrows),
    'the arrow branch no longer moves focus itself; having stopped the event'
    + ' it is the only thing that can');
});
