// The resolver runs before first paint and is the only thing that sets
// data-bs-theme, so every source of a theme choice goes through it.
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.join(__dirname, '..', '..', 'share', 'public', 'javascripts', 'netdisco-theme.js'), 'utf8');

function load({ configured, osDark }) {
  const attrs = {};
  const links = [];
  const listeners = [];
  const root = {
    dataset: { ndThemeDefault: configured, ndThemeRoot: '/t/x/theme/' },
    setAttribute: (k, v) => { attrs[k] = v; },
    removeAttribute: (k) => { delete attrs[k]; },
  };
  const query = { matches: osDark, addEventListener: (ev, fn) => listeners.push(fn) };
  const document = {
    documentElement: root,
    head: { appendChild: (el) => links.push(el) },
    querySelector: (sel) => links.find((l) => sel.includes(`"${l.dataset.ndThemeSheet}"`)) || null,
    createElement: () => ({ dataset: {} }),
  };
  const window = { matchMedia: () => query, document };
  const sandbox = { window, document };
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  const flip = (dark) => { query.matches = dark; listeners.forEach((fn) => fn()); };
  return { attrs, links, flip, nd: window.ndTheme };
}

test('ndTheme__auto_with_a_dark_os__sets_dark', () => {
  assert.equal(load({ configured: 'auto', osDark: true }).attrs['data-bs-theme'], 'dark');
});

test('ndTheme__auto_with_a_light_os__leaves_no_attribute', () => {
  assert.equal(load({ configured: 'auto', osDark: false }).attrs['data-bs-theme'], undefined);
});

test('ndTheme__auto__follows_an_os_change', () => {
  const t = load({ configured: 'auto', osDark: false });
  t.flip(true);
  assert.equal(t.attrs['data-bs-theme'], 'dark');
  t.flip(false);
  assert.equal(t.attrs['data-bs-theme'], undefined);
});

test('ndTheme__configured_classic__sets_it_without_another_sheet', () => {
  const t = load({ configured: 'classic', osDark: true });
  assert.equal(t.attrs['data-bs-theme'], 'classic');
  assert.equal(t.links.length, 0);
});

test('ndTheme__auto_resolving_dark__links_no_extra_sheet', () => {
  assert.equal(load({ configured: 'auto', osDark: true }).links.length, 0);
});

test('ndTheme__no_configured_theme__leaves_no_attribute', () => {
  assert.equal(load({ configured: '', osDark: true }).attrs['data-bs-theme'], undefined);
});

test('ndTheme__higher_priority_source__overrides_and_links_its_sheet', () => {
  const t = load({ configured: '', osDark: false });
  t.nd.sources.unshift(() => 'dark');
  t.nd.apply();
  assert.equal(t.attrs['data-bs-theme'], 'dark');
  assert.equal(t.links.length, 1);
  assert.equal(t.links[0].href, '/t/x/theme/dark.css');
  assert.equal(t.links[0].rel, 'stylesheet');
  t.nd.apply();
  assert.equal(t.links.length, 1, 'a second apply must not link the sheet twice');
});

test('ndTheme__source_name_with_path_characters__is_url_encoded', () => {
  const t = load({ configured: '', osDark: false });
  t.nd.sources.unshift(() => '../x');
  t.nd.apply();
  assert.equal(t.links[0].href, '/t/x/theme/..%2Fx.css');
});

test('ndTheme__source_returning_nothing__defers_to_the_next', () => {
  const t = load({ configured: 'classic', osDark: false });
  t.nd.sources.unshift(() => undefined);
  t.nd.apply();
  assert.equal(t.attrs['data-bs-theme'], 'classic');
});

test('ndTheme__configured_light__leaves_no_attribute', () => {
  const t = load({ configured: 'light', osDark: true });
  assert.equal(t.attrs['data-bs-theme'], undefined);
  assert.equal(t.links.length, 0);
});

test('ndTheme__source_choosing_light__leaves_no_attribute_and_links_nothing', () => {
  const t = load({ configured: 'classic', osDark: true });
  assert.equal(t.attrs['data-bs-theme'], 'classic');
  t.nd.sources.unshift(() => 'light');
  t.nd.apply();
  assert.equal(t.attrs['data-bs-theme'], undefined);
  assert.equal(t.links.length, 0);
});
