// Guards the handover of the per-tab chrome to the pane response.
//
// The csv download link and the device page's sidebar reset link used to be
// rebuilt in the browser after every swap, from a serialization of the form
// that had just been submitted. They now arrive with the pane as hx-swap-oob
// elements built by App::Netdisco::Util::Web::pane_chrome, so the browser
// keeps only what no response can answer.
//
// A SOURCE ASSERTION. Whether the swapped chrome is correct is a browser
// question and is checked by the Playwright harness and by xt/62; these checks
// only stop the client-side rebuild being reintroduced beside it, which would
// leave two writers for one href and no way to tell which won.

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const VIEWS = path.join(ROOT, 'share', 'views');
const SHELLS = ['device.tt', 'search.tt', 'report.tt', 'admintask.tt'];

const netdiscoSource = fs.readFileSync(
  path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco.js'), 'utf8');

test('netdiscoJs__now_the_response_carries_the_chrome__rebuilds_none_of_it', () => {
  for (const banned of ['update_csv_download_link', 'ndCsv',
                        'nd_sidebar-reset-link']) {
    assert.ok(!netdiscoSource.includes(banned),
      'netdisco.js still builds pane chrome by hand: ' + banned
      + '; answer with an hx-swap-oob element from the route instead');
  }
});

// htmx drops an out-of-band element whose id is nowhere in the page without a
// word: it builds no swap task for it and removes it from the response, which
// reads as a link quietly going stale rather than as a failure. Counting the
// markers the response offered against the tasks built from them is the only
// place that difference is still visible, so both halves of the comparison
// have to survive an edit.
test('netdiscoJs__out_of_band_chrome_with_no_target__is_reported', () => {
  const swapListener = netdiscoSource.slice(
    netdiscoSource.indexOf("addEventListener('htmx:before:swap'"));
  assert.notStrictEqual(swapListener, '',
    'netdisco.js no longer listens for htmx:before:swap');
  assert.match(swapListener, /hx-swap-oob/,
    'the response is no longer counted for the out-of-band chrome it offered');
  assert.match(swapListener, /task\.type === 'oob'/,
    'the tasks htmx built are no longer counted against it');
  assert.match(swapListener, /nd_report_script_error\(/,
    'a missed out-of-band target must reach the error reporter, not just the console');
});

// The sidebar fact is declared by the sidebar templates, and whether the reader
// has collapsed the sidebar is not the route's business, so both stay here.
test('netdiscoJs__the_state_no_response_knows__is_still_applied_on_submit', () => {
  for (const kept of ['copy_navbar_to_sidebar(submittedTab)',
                      'nd_apply_sidebar(submittedTab)']) {
    assert.ok(netdiscoSource.includes(kept),
      'the submit listener no longer applies ' + kept);
  }
});

// htmx fires one after-swap event per response, on the element that made the
// request, and puts the swap target on the context. A listener reading
// evt.detail.target therefore reads undefined and throws on the next property,
// inside the swap listener, where the throw takes the loading indicator down
// with it. The shape is silent about the change: nothing warns, the listener
// simply stops working.
test('swapListeners__the_pane_they_act_on__is_read_from_the_context', () => {
  for (const file of ['netdisco.js', 'netdisco-admin.js', 'netdisco-netmap.js']) {
    const source = fs.readFileSync(
      path.join(ROOT, 'share', 'public', 'javascripts', file), 'utf8');
    assert.ok(!source.includes('evt.detail.target'),
      file + ' reads the swap target from the event detail, where it no longer is');
  }
});

test('pageShells__the_csv_marker_the_browser_read__is_gone_from_every_shell', () => {
  for (const shell of SHELLS) {
    const source = fs.readFileSync(path.join(VIEWS, shell), 'utf8');
    assert.ok(!source.includes('data-nd-csv'),
      shell + ' still declares data-nd-csv, which nothing reads');
  }
});
