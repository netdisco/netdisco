// Guards reaching an item in the navbar's dropend submenus, by key and by
// pointer.
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
const netdiscoCss = fs.readFileSync(
  path.join(ROOT, 'share', 'public', 'css', 'netdisco.css'), 'utf8');

// Comments are stripped first: they quote selectors and property names, and a
// rule found inside one would be evidence of nothing.
function declarations(css, selector) {
  const stripped = css.replace(/\/\*[\s\S]*?\*\//g, '');
  const start = stripped.indexOf(selector + ' {');
  assert.notEqual(start, -1, 'netdisco.css carries a rule for ' + selector);
  const body = stripped.slice(start + selector.length + 2);
  return body.slice(0, body.indexOf('}'));
}

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
// Sideways movement is the other half of walking a menu by key, and nothing
// else on the page implements it: Bootstrap's own handler answers only to the
// up and down arrows and Escape.
test('navbarSubmenu__walking_sideways__moves_into_the_list_and_back_out', () => {
  const from = source.indexOf("if (event.key === 'ArrowRight' || event.key === 'ArrowLeft')");
  assert.ok(from > 0,
    'the submenu keydown listener no longer answers the left and right arrows,'
    + ' so a keyboard cannot enter a list that opens to the side');
  const sideways = source.slice(from, source.indexOf('if (!submenu) { return }', from));
  assert.match(sideways, /event\.preventDefault\(\)/,
    'the sideways branch no longer stops the page scrolling under the menu');
  assert.match(sideways, /\.dropdown-menu > li > \.dropdown-item/,
    'the sideways branch no longer names the submenu item it moves onto');
  assert.match(sideways, /landing\.focus\(\)/,
    'the sideways branch no longer moves focus, which is all it exists to do');
});

// The category below a category is only reachable if stepping stays out of the
// list the focused one holds open, which is the whole point of the branch.
test('navbarSubmenu__stepping_off_a_category__stays_out_of_its_open_list', () => {
  const from = source.indexOf("event.target === category\n      && (event.key === 'ArrowUp'");
  assert.ok(from > 0,
    'the listener no longer steps between categories itself, so the arrows fall'
    + " back to Bootstrap, which descends into the category's own open list");
  const branch = source.slice(from, source.indexOf('if (!submenu) { return }', from));
  assert.match(branch, /:scope > li > \.dropdown-item/,
    'the category branch no longer restricts itself to the menu\'s own entries,'
    + ' so items inside an open list are stepped through again');
  assert.match(branch, /event\.stopPropagation\(\)/,
    'the category branch no longer stops the event, so Bootstrap moves focus a'
    + ' second time after it');
});

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

// A submenu is held open by the pointer being inside the category, and the
// submenu is a descendant of it, so the two boxes have to touch. Any gap is
// dead space that drops the hover, and the slower the pointer the more surely
// it lands there.
test('navbarSubmenu__so_the_pointer_can_reach_it__touches_its_category', () => {
  const rule = declarations(netdiscoCss, '.dropend > .dropdown-menu');
  const margin = /margin-left:\s*([^;]+);/.exec(rule);
  assert.ok(margin, '.dropend > .dropdown-menu sets no margin-left');
  const value = margin[1].trim();
  // A bare 0 carries no unit and is as good as a negative length here.
  const px = /^(-?[\d.]+)(px)?$/.exec(value);
  assert.ok(px && (px[2] || Number(px[1]) === 0),
    'margin-left is "' + value + '"; it must be a pixel length or zero, and'
    + ' a variable such as --bs-dropdown-spacer is a positive gap the pointer'
    + ' falls into');
  assert.ok(Number(px[1]) <= 0,
    'margin-left is ' + value + ', which separates the submenu from the'
    + ' category that opens it; a pointer crossing that strip loses the hover'
    + ' and the submenu disappears');
});
