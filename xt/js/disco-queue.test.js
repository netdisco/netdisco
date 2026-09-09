// Guards the Discover box on the front page queueing its job over ajax.
//
// Posting the form navigated to the job queue when a job was accepted and back
// to the front page when it was refused, and the front page is where the reader
// already was, so a refusal looked exactly like nothing happening. An
// unresolvable hostname, a prefix wider than /22 and a value that is not an
// address at all are all refused, and each now says so.
//
// The action's own admin route already answered 400 for a device it will not
// take, so nothing on the server changed.
//
// A SOURCE ASSERTION. Whether a toast appears in a browser is checked by the
// Playwright harness; these checks stop the mechanism being undone by an edit
// that looks harmless.

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const source = fs.readFileSync(
  path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco.js'), 'utf8');

function body(name) {
  const from = source.indexOf('function ' + name);
  assert.notEqual(from, -1, 'netdisco.js still defines ' + name);
  let depth = 0;
  for (let j = source.indexOf('{', from); j < source.length; j += 1) {
    if (source[j] === '{') depth += 1;
    if (source[j] === '}') { depth -= 1; if (depth === 0) return source.slice(from, j + 1); }
  }
  throw new Error('unbalanced braces in ' + name);
}

test('discoQueue__submitting_the_box__asks_the_action_s_own_admin_route', () => {
  const fn = body('nd_queue_disco_job');
  assert.match(fn, /ndRequest\.post\(/,
    'the Discover box no longer queues over ajax, so a refused job navigates'
    + ' back to the page it came from and reports nothing');
  assert.match(fn, /'\/ajax\/control\/admin\/' \+ action/,
    "the Discover box no longer posts to the action's own admin route, which is"
    + ' what answers 400 for a device it will not take');
});

test('discoQueue__whichever_way_it_lands__says_what_happened', () => {
  const fn = body('nd_queue_disco_job');
  assert.match(fn, /response\.ok/,
    'the Discover box no longer reads the response, so a refusal reads as a'
    + ' success');
  assert.match(fn, /ndToast\.info\(/, 'nothing reports a queued job');
  assert.match(fn, /ndToast\.error\(/,
    'nothing reports a refused job, which is the whole point of the change');
  // Two of them: the request can fail before there is a response to read.
  assert.equal((fn.match(/ndToast\.error\(/g) || []).length, 2,
    'a request that never lands is not reported, so a backend that is down'
    + ' looks the same as nothing happening');
});

// The search dropdowns fill their box by asking the document for it, so while
// this form shared that handler a value left in the navbar search took
// precedence and submitted this form as a plain discover.
test('discoQueue__no_longer_sharing_the_search_dropdown__owns_its_own_clicks', () => {
  const shared = source.slice(source.indexOf(".nd_navsearchgo-specific'"));
  const upToNextBlock = shared.slice(0, shared.indexOf('discoForm'));
  assert.ok(!upToNextBlock.includes('discodevs'),
    'the search dropdown handler reaches for the Discover box again, so a value'
    + ' in the navbar search decides what this form submits');
  assert.match(source, /form\[action\$="\/admin\/discodevs"\]/,
    'nothing binds the Discover form itself any more');
});
