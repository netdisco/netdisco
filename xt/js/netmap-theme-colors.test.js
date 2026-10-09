// The canvas cannot see stylesheets, so a theme reaches the map's label, link
// and selection colors only through the --nd-netmap-* tokens read here.
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const src = fs.readFileSync(
  path.join(__dirname, '..', '..', 'share', 'public', 'javascripts', 'netdisco-netmap.js'),
  'utf8'
);

test('netmapThemeColor__defined__reads_the_root_custom_property', () => {
  assert.match(src, /function netmapThemeColor\(name, fallback\)/);
  assert.match(src, /getComputedStyle\(document\.documentElement\)\.getPropertyValue\(name\)/);
});

test('netmapThemeColor__empty_value__returns_the_fallback', () => {
  const body = src.slice(src.indexOf('function netmapThemeColor'));
  assert.match(body.slice(0, body.indexOf('\n}')), /\|\| fallback/);
});

test('netmapColors__label_link_and_selection__come_from_tokens', () => {
  assert.match(src, /colors\.label = netmapThemeColor\('--nd-netmap-label', '#212529'\)/);
  assert.match(src, /colors\.link = netmapThemeColor\('--nd-netmap-link', '#adb5bd'\)/);
  assert.match(src, /colors\.select = netmapThemeColor\('--nd-netmap-select', '#0d6efd'\)/);
});

test('netmapColors__drawing_code__holds_no_hardcoded_theme_color', () => {
  assert.doesNotMatch(src, /fillStyle = '#333'/);
  assert.doesNotMatch(src, /strokeStyle = '#0d6efd'/);
  assert.doesNotMatch(src, /linkColor\(\(\) => 'rgba/);
});

test('netmapColors__speed_label__comes_from_a_token', () => {
  assert.match(src, /colors\.speed = netmapThemeColor\('--nd-netmap-speed', '#212529'\)/);
});

test('netmapColors__theme_change__re_reads_colors_and_redraws', () => {
  assert.match(src, /new MutationObserver\(/);
  assert.match(src, /attributeFilter: \['data-bs-theme'\]/);
  const body = src.slice(src.indexOf('new MutationObserver('));
  const callback = body.slice(0, body.indexOf('});'));
  assert.match(callback, /readNetmapColors\(\)/);
  assert.match(callback, /fg\.zoom\(fg\.zoom\(\)\)/);
});

test('netmapColors__teardown__disconnects_the_theme_observer', () => {
  assert.match(src, /graph\.themeObserver\.disconnect\(\)/);
});

test('netmapColors__theme_change__is_not_read_from_the_os', () => {
  assert.doesNotMatch(src, /prefers-color-scheme/);
});

test('netmapColors__canvas_styles__are_never_assigned_a_string_literal', () => {
  assert.doesNotMatch(src, /(fillStyle|strokeStyle)\s*=\s*['"]/);
});
