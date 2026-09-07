// Guards the global script-error reporter registered in the first
// $(document).ready block of share/public/javascripts/netdisco.js: an
// uncaught exception or a failed htmx swap must reach the console every time
// and the user once per page, not once per page load's first mistake only
// and not once per mistake forever.
//
// The block under test is extracted from the shipped source by text
// position, not copied, so this cannot pass against a helper that no longer
// says what the copy said.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const source = fs.readFileSync(
  path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco.js'), 'utf8');

// The reporter's declarations run from ndReported's own var statement to the
// ready block's own closing "});", which is the first zero-indent "});"
// after that point: every statement the reporter adds is indented, so only
// the enclosing ready block's own close can produce that line.
function extractReporterBlock() {
  const start = source.indexOf('var ndReported = false;');
  assert.notStrictEqual(start, -1, 'nd_report_script_error setup is not defined in netdisco.js');
  const end = source.indexOf('\n});', start);
  assert.notStrictEqual(end, -1, 'could not find the end of the ready block holding the reporter');
  return source.slice(start, end);
}

function harness() {
  const windowListeners = {};
  const bodyListeners = {};
  const errorCalls = [];
  const toastrCalls = [];

  const windowMock = {
    addEventListener: (name, fn) => { windowListeners[name] = fn },
  };
  const documentMock = {
    body: { addEventListener: (name, fn) => { bodyListeners[name] = fn } },
  };
  const consoleMock = { error: (...args) => errorCalls.push(args) };
  const toastrMock = { error: (message) => toastrCalls.push(message) };

  new Function('window', 'document', 'console', 'toastr', extractReporterBlock())(
    windowMock, documentMock, consoleMock, toastrMock);

  return {
    fireError: (message, error) => windowListeners.error({ message, error }),
    fireRejection: (reason) => windowListeners.unhandledrejection({ reason }),
    fireHtmxError: (detail) => bodyListeners['htmx:error']({ detail }),
    errorCalls,
    toastrCalls,
  };
}

test('scriptError__with_a_message_and_an_error__logs_and_toasts_once', () => {
  const h = harness();
  h.fireError('boom', new Error('boom'));
  assert.strictEqual(h.errorCalls.length, 1, 'the console must carry the detail every time');
  assert.strictEqual(h.toastrCalls.length, 1, 'the user must be told something failed');
});

test('scriptError__a_second_error_on_the_same_page__logs_again_but_toasts_no_more', () => {
  const h = harness();
  h.fireError('first', new Error('first'));
  h.fireError('second', new Error('second'));
  assert.strictEqual(h.errorCalls.length, 2,
    'every error belongs in the console, or a second, different failure is invisible');
  assert.strictEqual(h.toastrCalls.length, 1,
    'a toast per error would be noise once several unrelated things fail on one page');
});

test('scriptError__a_bare_cross_origin_script_error__is_ignored', () => {
  const h = harness();
  h.fireError('Script error.', undefined);
  assert.strictEqual(h.errorCalls.length, 0,
    'a script from another origin reports no detail at all, so logging it teaches nothing');
  assert.strictEqual(h.toastrCalls.length, 0);
});

test('unhandledRejection__reports_like_any_other_script_error', () => {
  const h = harness();
  h.fireRejection(new Error('rejected'));
  assert.strictEqual(h.errorCalls.length, 1, 'a rejected promise is as silent as a thrown error otherwise');
  assert.strictEqual(h.toastrCalls.length, 1);
});

// htmx carries four different failures on one event: a request that never
// arrived, one that timed out, one that was abandoned when a newer request
// replaced it, and an exception thrown while displaying an answer that did
// arrive. Only the last of those is a script error. The first three reach the
// reader as the pane's own failure message, which is written by a separate
// listener above this block and must not also raise a toast, or every
// abandoned tab switch would.
test('htmxError__an_answer_that_could_not_be_displayed__reports_like_a_script_error', () => {
  const h = harness();
  h.fireHtmxError({ ctx: { response: { status: 200 } }, error: new Error('bad content type') });
  assert.strictEqual(h.errorCalls.length, 1,
    'a swap htmx cannot display is otherwise an event nobody listens to');
  assert.strictEqual(h.toastrCalls.length, 1);
});

test('htmxError__a_failure_with_no_request_behind_it__reports_like_a_script_error', () => {
  const h = harness();
  h.fireHtmxError({ error: new Error('handler threw') });
  assert.strictEqual(h.errorCalls.length, 1,
    'an exception inside an htmx handler reaches nobody else');
  assert.strictEqual(h.toastrCalls.length, 1);
});

test('htmxError__a_request_that_never_arrived__is_left_to_the_pane_handler', () => {
  const h = harness();
  h.fireHtmxError({ ctx: {}, error: new Error('offline') });
  assert.strictEqual(h.errorCalls.length, 0,
    'the pane says so in the pane; a toast beside it fires on every abandoned tab switch too');
  assert.strictEqual(h.toastrCalls.length, 0);
});

// htmx sets the response before it reads the body, so a request abandoned
// during the read reaches this handler looking like one that was answered.
// Clicking a second tab while the first is still arriving is an ordinary
// thing to do and must not raise anything at all.
test('htmxError__an_abandoned_request_that_had_begun_answering__raises_nothing', () => {
  const h = harness();
  const aborted = new Error('aborted');
  aborted.name = 'AbortError';
  h.fireHtmxError({ ctx: { response: { status: 200 } }, error: aborted });
  assert.strictEqual(h.errorCalls.length, 0,
    'a tab switch would otherwise report a script error on every click');
  assert.strictEqual(h.toastrCalls.length, 0);
});
