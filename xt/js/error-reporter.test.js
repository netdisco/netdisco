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
    fireSwapError: (detail) => bodyListeners['htmx:swapError']({ detail }),
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

test('htmxSwapError__reports_like_any_other_script_error', () => {
  const h = harness();
  h.fireSwapError('bad content type');
  assert.strictEqual(h.errorCalls.length, 1,
    'a swap htmx cannot display is otherwise an event nobody listens to');
  assert.strictEqual(h.toastrCalls.length, 1);
});
