// Guards the handover of the sidebar form submit to htmx.
//
// A tab pane is loaded by submitting its sidebar form, and everything that
// reloads a pane without a person clicking Search does it that way: the tab
// switch, the Ports column and filter controls, the jobqueue countdown, and
// every admin table button. That used to go through an nd_submit() helper
// which built a SubmitEvent by hand. htmx.trigger() replaces it.
//
// Two facts make the substitute work, both read from the vendored htmx.min.js:
// its form listener reads only the event type and the element, never the
// event's class, trust or submitter, and htmx.trigger dispatches a bubbling
// CustomEvent, so the delegated document listener in netdisco.js that updates
// the csv link, the reset link and the sidebar still sees it.
//
// jQuery's .trigger('submit') is not a substitute and is banned below. It runs
// only handlers jQuery itself bound, so htmx's native listener never sees it,
// and it then calls form.submit(), which navigates the whole page. The plain
// .submit() calls left in netdisco.js are deliberate: the navbar search boxes
// really do navigate, and one call binds a handler rather than firing one.
//
// A SOURCE ASSERTION. Whether a submit reaches the pane is a browser question
// and is checked by the Playwright harness; these checks only stop the
// mechanism being reintroduced by an edit that looks harmless.

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const JS_DIR = path.join(ROOT, 'share', 'public', 'javascripts');

const ourFiles = fs.readdirSync(JS_DIR).filter((file) => file.startsWith('netdisco'));

test('netdiscoJs__now_htmx_dispatches_the_submit__builds_no_event_by_hand', () => {
  for (const file of ourFiles) {
    const source = fs.readFileSync(path.join(JS_DIR, file), 'utf8');
    assert.ok(!/\bnew SubmitEvent\b/.test(source),
      file + " builds a SubmitEvent by hand; call htmx.trigger(form, 'submit')"
      + ' and let the library dispatch it');
    assert.ok(!/\.trigger\(\s*['"]submit['"]/.test(source),
      file + " calls jQuery's .trigger('submit'), which htmx's native listener"
      + ' never sees and which ends in a full page navigation');
  }
});

// A global, so a site-local template may be calling it. Its removal is
// reported by checksitelocal rather than by anything the browser shows.
test('netdiscoJs__after_the_handover__ships_no_ndSubmit_helper', () => {
  for (const file of ourFiles) {
    assert.ok(!fs.readFileSync(path.join(JS_DIR, file), 'utf8').includes('nd_submit'),
      file + " still names nd_submit; use htmx.trigger('#<tab>_form', 'submit')");
  }
});

// The bans above are satisfied by a file that reloads no pane at all, so both
// files are also checked to still be asking the library for the submit.
test('netdiscoJs__with_the_helper_gone__still_reloads_a_pane_through_htmx_trigger', () => {
  for (const file of ['netdisco.js', 'netdisco-admin.js']) {
    const source = fs.readFileSync(path.join(JS_DIR, file), 'utf8');
    assert.match(source, /htmx\.trigger\([^)]*,\s*['"]submit['"]\)/,
      file + ' reloads a pane by some other means than htmx.trigger');
  }
});
