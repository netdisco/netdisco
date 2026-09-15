// Guards the handover of browser history to htmx.
//
// The routes answer a pane request with HX-Push-Url or HX-Replace-Url, so htmx
// writes the address bar. htmx 2 answered a back press from a snapshot of the
// body it had put in sessionStorage, and that snapshot carried the layout's
// script tags, which the restore re-inserted and re-ran against a document
// that had already run them: "Identifier 'ndTables' has already been declared"
// and the netmap's "graph" beside it, with the page half dead. Two settings
// closed it. htmx 4 keeps no snapshot, but it answers a traverse by fetching
// the page and swapping it into the body, which re-inserts those same script
// tags, so one setting still stands between a working back button and a broken
// one: it asks for a real page load instead.
//
// A SOURCE ASSERTION. Whether back and forward work is a browser question and
// is checked by the Playwright harness; these checks only stop the mechanism
// being reintroduced by an edit that looks harmless.

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const JS_DIR = path.join(ROOT, 'share', 'public', 'javascripts');
const LAYOUT = path.join(ROOT, 'share', 'views', 'layouts', 'main.tt');

const netdiscoSource = fs.readFileSync(path.join(JS_DIR, 'netdisco.js'), 'utf8');
const layoutSource = fs.readFileSync(LAYOUT, 'utf8');

// Re-declaring a default is worse than declaring nothing: it reads as a
// decision this tree made, so the next reader keeps it through an upgrade that
// changes what the default means.
test('netdiscoJs__settings_htmx_now_makes_itself__are_declared_nowhere', () => {
  for (const gone of ['historyCacheSize', 'refreshOnHistoryMiss']) {
    assert.ok(!netdiscoSource.includes(gone),
      'netdisco.js still sets htmx.config.' + gone + ', which the library removed');
  }
});

// Configuration has to be in place before htmx can issue anything.
// netdisco.js executes during parse, straight after htmx.min.js, so anything
// above these lines that reaches the network would run first.
// The library answers Back by fetching the page and swapping it into the body,
// which re-inserts the layout's script tags and runs them a second time against
// a document that already ran them. Every top-level declaration in them is then
// declared twice and the page dies. Asking for a real reload is the same round
// trip without that, and it is the only setting standing between a working Back
// button and a broken one, so it is asserted rather than left to a comment.
test('netdiscoJs__a_history_traverse__is_asked_for_as_a_real_page_load', () => {
  assert.match(netdiscoSource, /htmx\.config\.history\s*=\s*'reload'/,
    'netdisco.js must set htmx.config.history to reload, or Back re-runs every script tag');
});

test('netdiscoJs__the_htmx_configuration__precedes_every_other_statement', () => {
  const firstCode = netdiscoSource.split('\n')
    .find((line) => line.trim() !== '' && !line.trim().startsWith('//'));
  assert.match(firstCode, /^htmx\.config\./,
    'the htmx configuration must be the first code in netdisco.js, not ' + firstCode);
});

test('netdiscoJs__now_htmx_owns_history__drives_none_of_it_by_hand', () => {
  for (const banned of ['history.pushState', 'history.replaceState', 'popstate',
                        'is_from_state_event', 'update_browser_history']) {
    assert.ok(!netdiscoSource.includes(banned),
      'netdisco.js still drives history by hand: ' + banned
      + '; answer with HX-Push-Url or HX-Replace-Url from the route instead');
  }
});

// The library was vendored for the one .deserialize() call the popstate
// handler made, so it goes with it rather than staying as an unreferenced
// download on every page load.
test('jqueryDeserialize__after_the_popstate_handler_went__is_shipped_nowhere', () => {
  assert.ok(!fs.existsSync(path.join(JS_DIR, 'jquery-deserialize.js')),
    'the library is not shipped');
  assert.ok(!layoutSource.includes('jquery-deserialize'),
    'main.tt does not load it');

  const manifest = fs.readFileSync(path.join(ROOT, 'MANIFEST'), 'utf8');
  assert.ok(!manifest.includes('jquery-deserialize'),
    'MANIFEST does not name it');

  for (const file of fs.readdirSync(JS_DIR)) {
    if (!file.startsWith('netdisco')) continue;
    assert.ok(!fs.readFileSync(path.join(JS_DIR, file), 'utf8').includes('.deserialize('),
      file + ' still calls the removed .deserialize()');
  }
});
