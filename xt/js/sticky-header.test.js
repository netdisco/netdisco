// Guards the results table header staying in view while its rows scroll.
//
// It was a vendored jQuery plug-in, floatThead, which cloned the table into a
// fixed-position wrapper and had to be destroyed and rebuilt on every sidebar
// toggle and every pane swap. The stylesheet does it now with one declaration,
// so there is nothing left to reapply, and the risk moves from "a call site was
// missed" to "a rule was edited without knowing what it was for".
//
// A SOURCE ASSERTION. Whether the header actually stays put is a browser
// question: the job queue is the only table that carries the class, and on the
// demo data that page holds no rows and does not scroll, so no fixture here can
// see it. These checks stop the mechanism being undone by an edit that looks
// harmless.

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const JS_DIR = path.join(ROOT, 'share', 'public', 'javascripts');
const CSS_DIR = path.join(ROOT, 'share', 'public', 'css');
const LAYOUT = path.join(ROOT, 'share', 'views', 'layouts', 'main.tt');

const netdiscoCss = fs.readFileSync(path.join(CSS_DIR, 'netdisco.css'), 'utf8');
const layoutSource = fs.readFileSync(LAYOUT, 'utf8');

const HEADER_RULE = 'div.content > div.tab-content table.nd_floatinghead thead';

// Comments are stripped first: they quote selectors and property names, and a
// rule found inside one would be evidence of nothing.
function declarations(css, selector) {
  const stripped = css.replace(/\/\*[\s\S]*?\*\//g, '');
  const start = stripped.indexOf(selector + ' {');
  assert.notEqual(start, -1, 'netdisco.css carries a rule for ' + selector);
  const body = stripped.slice(start + selector.length + 2);
  return body.slice(0, body.indexOf('}'));
}

test('stickyHeader__the_results_table_header__is_stuck_below_the_fixed_navbar', () => {
  const rule = declarations(netdiscoCss, HEADER_RULE);

  assert.match(rule, /position:\s*sticky/,
    HEADER_RULE + ' must be sticky, or its header scrolls away with the rows');

  const offset = rule.match(/\btop:\s*(\d+)px/);
  assert.ok(offset, HEADER_RULE + ' must declare a top offset in px');

  // The offset is the bar's height and nothing else, so a header that came to
  // rest under the bar or short of it would be a bug in one of the two numbers.
  // Tying them here means re-heighting the bar fails loudly instead of leaving
  // the header floating in the gap.
  const navbar = declarations(netdiscoCss, '.navbar > .container');
  const height = navbar.match(/\bmin-height:\s*(\d+)px/);
  assert.ok(height, '.navbar > .container must declare its height in px');

  assert.equal(offset[1], height[1],
    'the sticky header rests at ' + offset[1] + 'px but the navbar is '
    + height[1] + 'px tall; the two are the same measurement');
});

test('stickyHeader__the_rows_passing_beneath_it__do_not_show_through', () => {
  const rule = declarations(netdiscoCss, HEADER_RULE);

  assert.match(rule, /background-color:\s*\S+/,
    HEADER_RULE + ' must paint a background, or scrolled rows show through it');
  assert.doesNotMatch(rule, /background-color:\s*(?:transparent|[^;]*\b0\s*\))/,
    HEADER_RULE + ' must paint an opaque background, not a see-through one');
  assert.match(rule, /--bs-table-bg:\s*\S+/,
    HEADER_RULE + ' must set --bs-table-bg: the framework paints the cells from '
    + 'it, and they cover the background on the thead itself');
});

test('stickyHeader__the_box_it_sticks_within__is_not_made_a_scroll_container', () => {
  // Any overflow but visible on an ancestor scopes the header to that box, and
  // it then never reaches the viewport offset above. This is the ancestor whose
  // default the stylesheet already overrides.
  assert.match(declarations(netdiscoCss, '.tab-content'), /overflow:\s*visible/,
    '.tab-content must stay overflow: visible, or the sticky header cannot stick');
});

test('floatThead__now_the_stylesheet_does_it__is_called_from_no_javascript', () => {
  for (const file of fs.readdirSync(JS_DIR)) {
    if (!file.startsWith('netdisco')) continue;
    assert.ok(!fs.readFileSync(path.join(JS_DIR, file), 'utf8').includes('floatThead('),
      file + ' still calls the removed floatThead plug-in');
  }
});

test('floatThead__now_the_stylesheet_does_it__is_shipped_nowhere', () => {
  assert.ok(!fs.existsSync(path.join(JS_DIR, 'jquery.floatThead.js')),
    'the plug-in is not shipped');
  assert.ok(!layoutSource.includes('floatThead'),
    'main.tt does not load it');

  assert.ok(!fs.readFileSync(path.join(ROOT, 'MANIFEST'), 'utf8').includes('floatThead'),
    'MANIFEST does not name it');

  const manifest = JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8'));
  assert.ok(!Object.keys(manifest.dependencies).includes('floatthead'),
    'package.json does not declare it');
});

test('floatThead__the_classes_it_generated__are_styled_by_no_stylesheet', () => {
  for (const file of fs.readdirSync(CSS_DIR)) {
    if (!file.endsWith('.css')) continue;
    assert.ok(!fs.readFileSync(path.join(CSS_DIR, file), 'utf8').includes('.floatThead-'),
      file + ' still styles a class only the removed plug-in generated');
  }
});
