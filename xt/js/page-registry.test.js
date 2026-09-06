// Guards the ndPages registry netdisco.js exposes so a page's script can
// drive itself without netdisco.js knowing which pages exist, and guards
// that the admin split actually moved the admin-only code out of
// netdisco.js and into netdisco-admin.js's own registration.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const JS_DIR = path.join(ROOT, 'share', 'public', 'javascripts');

const netdiscoSource = fs.readFileSync(path.join(JS_DIR, 'netdisco.js'), 'utf8');
const adminSource = fs.readFileSync(path.join(JS_DIR, 'netdisco-admin.js'), 'utf8');

// netdisco.js dereferences document.body.dataset at load and
// its ready blocks need a real jQuery, so this is a text check rather than
// an executed one; netdisco-admin.js below has no such top-level dependency
// and is loaded for real.
test('ndPages__is_declared_as_an_object_in_netdisco_js', () => {
  assert.match(netdiscoSource, /var ndPages\s*=\s*\{\};/);
});

function loadAdminModule() {
  const clickListeners = [];
  const changeListeners = [];
  const documentMock = {
    addEventListener: (name, fn) => {
      if (name === 'click') clickListeners.push(fn);
      if (name === 'change') changeListeners.push(fn);
    },
    body: { addEventListener: () => {} },
  };
  const ndPages = {};

  new Function('document', 'window', 'ndPages', adminSource)(documentMock, {}, ndPages);

  return { ndPages, clickListeners, changeListeners };
}

test('netdiscoAdminJs__loaded__registers_ndPages_admin_with_formInputs_innerView_and_ready', () => {
  const { ndPages } = loadAdminModule();
  assert.ok(ndPages.admin, 'netdisco-admin.js must register ndPages.admin');
  assert.strictEqual(typeof ndPages.admin.formInputs, 'function');
  assert.strictEqual(typeof ndPages.admin.innerView, 'function');
  assert.strictEqual(typeof ndPages.admin.ready, 'function');
});

// Selectors and identifiers that belong only to the moved admin code. A
// generic, page-agnostic exclusion for the jobqueue pane already carries the
// word "jobqueue" in netdisco.js's htmx:beforeRequest indicator handling
// (share/public/javascripts/netdisco.js, "jobqueue is excluded"), so this
// checks the admin-specific "nd_jobqueue" and "nd_countdown" tokens rather
// than the bare word.
const ADMIN_ONLY_TOKENS = [
  'nd_tokenbutton', 'nd_layer-three-link', 'nd_delete-me', 'nd_auth_method',
  'nd_token-copy', 'nd_acl_host_searcher', 'nd_topo_dev', 'nd_jobqueue', 'nd_countdown',
];

test('netdiscoJs__no_longer_contains_any_admin_only_selector', () => {
  for (const token of ADMIN_ONLY_TOKENS) {
    assert.ok(!netdiscoSource.includes(token), 'netdisco.js still contains admin-only token: ' + token);
  }
});

test('netdiscoAdminJs__carries_no_template_toolkit_directive', () => {
  assert.ok(!adminSource.includes('[%'), 'netdisco-admin.js must be static JavaScript, not a template');
});

test('netdiscoJs__drives_a_registered_page__through_ndPages_innerView_and_ready', () => {
  assert.match(netdiscoSource, /ndPages\[page\]\.innerView\(tab\)/, 'inner_view_processing must dispatch to a registered page');
  assert.match(netdiscoSource, /ndPages\[page\]\.ready\(\)/, 'the page ready block must dispatch to a registered page');
});

test('layout__on_an_admin_page_only__loads_netdisco_admin_js', () => {
  const layout = fs.readFileSync(path.join(ROOT, 'share', 'views', 'layouts', 'main.tt'), 'utf8');
  const tag = /\[% IF task %\][^\n]*netdisco-admin\.js[^\n]*\[% END %\]/;
  assert.match(layout, tag, 'the admin script tag must be wrapped in the task condition');
  assert.strictEqual((layout.match(/netdisco-admin\.js/g) || []).length, 1, 'the admin script is loaded once');
});
