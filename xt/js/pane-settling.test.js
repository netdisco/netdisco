// Guards holdUntilSettled() in share/public/javascripts/netdisco.js: an
// indicator that outlives the response, and a pane that stays out of view until
// its table has been built.
//
// The rule is asserted, not a table library's behaviour, because settling is
// read from MutationObserver and frames so that it survives the move off jQuery
// and any change of table library. Frames are pumped by the test, so nothing
// here waits on wall time.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const source = fs.readFileSync(
  path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco.js'), 'utf8');

// Take the shipped function text rather than a copy of it, so this cannot pass
// against a helper that no longer says what the copy said.
function extract(name) {
  const from = source.search(new RegExp('function\\s+' + name + '\\s*\\('));
  assert.notStrictEqual(from, -1, name + ' is not defined in netdisco.js');
  let depth = 0;
  for (let j = source.indexOf('{', from); j < source.length; j += 1) {
    if (source[j] === '{') depth += 1;
    if (source[j] === '}') { depth -= 1; if (depth === 0) return source.slice(from, j + 1); }
  }
  throw new Error('unbalanced braces in ' + name);
}

function harness({ now = () => 1000 } = {}) {
  const frames = [];
  const element = () => {
    const classes = new Set();
    return { classList: { add: (c) => classes.add(c), remove: (c) => classes.delete(c),
                          contains: (c) => classes.has(c) }, classes };
  };
  const pane = element();
  const indicator = element();
  let mutate = null;
  let disconnected = false;
  let clock = 0;

  const MutationObserver = function (fn) {
    mutate = fn;
    return { observe: () => {}, disconnect: () => { disconnected = true } };
  };
  const fn = new Function('MutationObserver', 'requestAnimationFrame', 'Date',
    extract('holdUntilSettled') + '; return holdUntilSettled;')(
    MutationObserver, (f) => frames.push(f), { now });

  return {
    run: () => fn(pane, indicator),
    runWith: (p, i) => fn(p, i),
    // One frame, `gap` milliseconds after the previous one. 16 is a frame at
    // 60Hz; a gap far larger than that is the thread having been busy.
    tick: (gap = 16) => { clock += gap; const f = frames.shift(); if (f) f(clock) },
    mutation: () => mutate(),
    settled: () => !pane.classList.contains('nd_pane-settling'),
    pane, indicator, element,
    get disconnected() { return disconnected },
    get pending() { return frames.length },
  };
}

test('holdUntilSettled__at_the_swap__hides_the_pane_and_keeps_the_indicator', () => {
  const h = harness();
  h.run();
  assert.ok(h.pane.classList.contains('nd_pane-settling'),
    'the pane must be out of view before anything can paint it');
  assert.ok(h.indicator.classList.contains('nd_indicator-held'),
    'the indicator must outlive the response htmx took it down for');
});

test('holdUntilSettled__frames_arriving_quietly_and_on_time__reveal_the_pane', () => {
  const h = harness();
  h.run();
  h.tick();
  h.tick();
  assert.ok(!h.settled(), 'one good frame is not evidence that the build has stopped');
  h.tick();
  assert.ok(h.settled(), 'the pane is revealed');
  assert.ok(!h.indicator.classList.contains('nd_indicator-held'), 'the indicator goes with it');
  assert.ok(h.disconnected, 'the observer must not outlive the hold');
});

test('holdUntilSettled__a_mutation_before_a_frame__starts_the_count_again', () => {
  const h = harness();
  h.run();
  h.tick();
  h.tick();
  h.mutation();
  h.tick();
  assert.ok(!h.settled(), 'a pane still being built has not settled');
  h.tick();
  h.tick();
  assert.ok(h.settled(), 'quiet again, so revealed');
});

// The defect this rule exists for. A table build has gaps of several hundred
// milliseconds where nothing changes because the thread is computing, and a
// quiet-only rule reveals in one of them: the indicator goes while the table is
// still moving. A frame that took far longer than a frame should is what says
// the thread was busy through it.
test('holdUntilSettled__quiet_frames_that_arrive_late__do_not_count', () => {
  const h = harness();
  h.run();
  h.tick();
  h.tick(400);
  h.tick(400);
  h.tick(400);
  assert.ok(!h.settled(), 'the thread was busy through every one of those frames');
  h.tick();
  h.tick();
  assert.ok(h.settled(), 'and revealed once frames come back on time');
});

test('holdUntilSettled__a_pane_that_never_goes_quiet__is_revealed_at_the_deadline', () => {
  let clock = 1000;
  const h = harness({ now: () => clock });
  h.run();
  for (let i = 0; i < 5; i += 1) { h.mutation(); h.tick() }
  assert.ok(h.pane.classList.contains('nd_pane-settling'), 'still building, still held');
  clock += 60000;
  h.mutation();
  h.tick();
  assert.ok(!h.pane.classList.contains('nd_pane-settling'),
    'past the deadline the pane is shown as it is, rather than a spinner for ever');
});

test('holdUntilSettled__a_pane_with_no_indicator__is_left_alone', () => {
  const h = harness();
  const pane = h.element();
  h.runWith(pane, null);
  assert.strictEqual(pane.classes.size, 0,
    'the job queue pane refreshes on a timer and carries no indicator: hiding it '
    + 'on every tick would be the flash this prevents');
  assert.strictEqual(h.pending, 0, 'and nothing is left watching frames');
});
