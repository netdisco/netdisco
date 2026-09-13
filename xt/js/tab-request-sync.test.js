// Guards the handover of request cancellation to htmx.
//
// Switching tabs abandons whatever the leaving tab was still fetching. That
// used to be a hand-written htmx.trigger(leavingForm, 'htmx:abort') in
// update_content. It is now hx-sync on each sidebar form, naming the sidebar
// they share, so the library holds one in-flight request per page and starts
// the new one by aborting the old.
//
// Deleting the trigger was not optional. Under hx-sync the in-flight request
// is recorded against the sync element, not against the form, so a trigger
// aimed at the form finds nothing to abort and quietly does nothing while
// still looking like working code.
//
// The strategy has to be replace. drop and abort both discard the NEW request,
// which is the tab the person just clicked, and every queue variant makes them
// wait for the answer they walked away from.
//
// A SOURCE ASSERTION. Which answer wins a race is a browser question and is
// checked by the Playwright harness; these checks only stop the mechanism
// being reintroduced by an edit that looks harmless.

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const JS_DIR = path.join(ROOT, 'share', 'public', 'javascripts');
const VIEWS = path.join(ROOT, 'share', 'views');

const PAGES = ['device.tt', 'search.tt', 'report.tt', 'admintask.tt'];

test('netdiscoJs__now_htmx_owns_cancellation__aborts_nothing_by_hand', () => {
  for (const file of fs.readdirSync(JS_DIR)) {
    if (!file.startsWith('netdisco')) continue;
    const source = fs.readFileSync(path.join(JS_DIR, file), 'utf8');
    assert.ok(!source.includes('htmx:abort'),
      file + ' triggers htmx:abort by hand; the request belongs to the'
      + ' hx-sync element now, so the trigger would be a no-op');
  }
});

// Set on each form rather than once on the sidebar they share: htmx 4 ends
// implicit attribute inheritance, so an inherited hx-sync would need rewriting
// with an :inherited suffix and a missed one fails without a console message.
// Hence the attribute is looked for inside the form's own opening tag.
for (const page of PAGES) {
  test('pageTemplate__' + page.replace('.tt', '') + '__syncs_its_form_on_the_sidebar', () => {
    const source = fs.readFileSync(path.join(VIEWS, page), 'utf8');

    const formTag = source.match(/<form id="[^>]*>/);
    assert.ok(formTag, page + ' renders no sidebar form');
    assert.match(formTag[0], /hx-sync="closest \.nd_sidebar:replace"/,
      page + ' must set the sync element and the replace strategy on the form'
      + ' itself, never on an ancestor for the form to inherit');

    // The sync element is resolved with element.closest(), and htmx 2.0.10
    // throws when that returns nothing, so the ancestor is load-bearing.
    assert.match(source, /class="nd_sidebar[ "]/,
      page + ' names a sidebar its forms cannot resolve');
  });
}
