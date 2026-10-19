// The resolver runs before first paint and is the only thing that sets
// data-bs-theme, so every source of a theme choice goes through it.
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.join(__dirname, '..', '..', 'share', 'public', 'javascripts', 'netdisco-theme.js'), 'utf8');

function load({ configured, osDark, stored, storageBlocked }) {
  const saved = stored === undefined ? {} : { 'netdisco-theme': stored };
  const localStorage = {
    getItem: (k) => (k in saved ? saved[k] : null),
    setItem: (k, v) => { saved[k] = String(v); },
    removeItem: (k) => { delete saved[k]; },
  };
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
  // A browser with site data blocked throws on touching localStorage at all,
  // not only on writing to it.
  Object.defineProperty(window, 'localStorage', {
    get: () => { if (storageBlocked) throw new Error('SecurityError'); return localStorage; },
  });
  const sandbox = { window, document };
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  const flip = (dark) => { query.matches = dark; listeners.forEach((fn) => fn()); };
  return { attrs, links, flip, saved, nd: window.ndTheme };
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

// A per-user choice from the user menu's switch, kept in the browser. It only
// counts while the configured default is auto: an admin who sets a theme
// outright has picked it for everyone.

test('ndTheme__auto_with_saved_dark__sets_dark_on_a_light_os', () => {
  assert.equal(load({ configured: 'auto', osDark: false, stored: 'dark' }).attrs['data-bs-theme'], 'dark');
});

test('ndTheme__auto_with_saved_light__leaves_no_attribute_on_a_dark_os', () => {
  assert.equal(load({ configured: 'auto', osDark: true, stored: 'light' }).attrs['data-bs-theme'], undefined);
});

test('ndTheme__saved_choice__holds_through_an_os_change', () => {
  const t = load({ configured: 'auto', osDark: false, stored: 'dark' });
  t.flip(false);
  assert.equal(t.attrs['data-bs-theme'], 'dark');
});

test('ndTheme__saved_choice_under_a_configured_theme__is_ignored', () => {
  assert.equal(load({ configured: 'classic', osDark: false, stored: 'dark' }).attrs['data-bs-theme'], 'classic');
  assert.equal(load({ configured: 'light', osDark: false, stored: 'dark' }).attrs['data-bs-theme'], undefined);
});

test('ndTheme__saved_value_other_than_light_or_dark__is_ignored', () => {
  // Anything else would be linked as a stylesheet, so a stale or tampered
  // value must not reach the sheet loader.
  const t = load({ configured: 'auto', osDark: false, stored: '../x' });
  assert.equal(t.attrs['data-bs-theme'], undefined);
  assert.equal(t.links.length, 0);
});

test('ndTheme__choose_dark__applies_and_saves_it', () => {
  const t = load({ configured: 'auto', osDark: false });
  t.nd.choose('dark');
  assert.equal(t.attrs['data-bs-theme'], 'dark');
  assert.equal(t.saved['netdisco-theme'], 'dark');
});

test('ndTheme__choose_auto__forgets_the_saved_choice_and_follows_the_os', () => {
  const t = load({ configured: 'auto', osDark: true, stored: 'light' });
  t.nd.choose('auto');
  assert.equal(t.attrs['data-bs-theme'], 'dark');
  assert.equal('netdisco-theme' in t.saved, false);
});

test('ndTheme__chosen__reports_the_saved_choice_or_auto', () => {
  const t = load({ configured: 'auto', osDark: false });
  assert.equal(t.nd.chosen(), 'auto');
  t.nd.choose('light');
  assert.equal(t.nd.chosen(), 'light');
});

test('ndTheme__blocked_storage__still_follows_the_os', () => {
  assert.equal(load({ configured: 'auto', osDark: true, storageBlocked: true }).attrs['data-bs-theme'], 'dark');
});

test('ndTheme__blocked_storage__choose_still_changes_this_page', () => {
  const t = load({ configured: 'auto', osDark: false, storageBlocked: true });
  t.nd.choose('dark');
  assert.equal(t.attrs['data-bs-theme'], 'dark');
  assert.equal(t.nd.chosen(), 'dark');
});
