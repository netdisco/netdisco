const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ROOT = path.join(__dirname, '..', '..');
const source = fs.readFileSync(
  path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco-daterange.js'), 'utf8');

// The arithmetic must be usable before there is a document, so the sandbox
// carries only enough window for the file's top level to run.
function loadCore() {
  const win = { addEventListener() {}, document: { addEventListener() {} } };
  const sandbox = { window: win, document: win.document };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  assert.ok(win.ndDateRange, 'the file did not publish window.ndDateRange');
  return win.ndDateRange;
}

const ndDateRange = loadCore();

// Fixed bases rather than "now", so a test that runs at midnight or on the
// 31st does not disagree with one that runs at noon on the 3rd.
const BASE = new Date(2026, 6, 4, 15, 47);       // Saturday 2026-07-04
const WINTER = new Date(2026, 0, 15, 15, 47);    // 2026-01-15, the other side of DST

test('presetRange__last_seven_days__spans_seven_days_including_today', () => {
  const { from, to } = ndDateRange.presetRange('last7', BASE);
  assert.equal(ndDateRange.formatDate(from), '2026-06-28');
  assert.equal(ndDateRange.formatDate(to), '2026-07-04');
});

test('presetRange__last_month__is_the_whole_of_the_previous_month', () => {
  const { from, to } = ndDateRange.presetRange('lastmonth', BASE);
  assert.equal(ndDateRange.formatDate(from), '2026-06-01');
  assert.equal(ndDateRange.formatDate(to), '2026-06-30');
});

test('presetRange__this_month_in_a_month_of_31_days__ends_on_the_31st', () => {
  const { from, to } = ndDateRange.presetRange('thismonth', BASE);
  assert.equal(ndDateRange.formatDate(from), '2026-07-01');
  assert.equal(ndDateRange.formatDate(to), '2026-07-31');
});

test('presetRange__last_thirty_days_across_a_month_boundary__counts_calendar_days', () => {
  const { from } = ndDateRange.presetRange('last30', BASE);
  assert.equal(ndDateRange.formatDate(from), '2026-06-05');
});

// The formatter reads the local getters. toISOString would convert to UTC and
// report the next day for anyone west of Greenwich in the evening, which is the
// one mistake this module exists to avoid.
test('formatDate__late_in_the_evening__reports_the_local_date', () => {
  assert.equal(ndDateRange.formatDate(new Date(2026, 8, 7, 23, 59)), '2026-09-07');
});

test('presetRange__either_side_of_a_daylight_saving_change__is_unaffected', () => {
  assert.equal(ndDateRange.formatDate(ndDateRange.presetRange('last7', WINTER).from), '2026-01-09');
});

test('presetRange__today__gives_that_day_for_both_ends', () => {
  const { from, to } = ndDateRange.presetRange('today', BASE);
  assert.equal(ndDateRange.formatDate(from), '2026-07-04');
  assert.equal(ndDateRange.formatDate(to), '2026-07-04');
});

test('presetRange__yesterday__gives_the_day_before_for_both_ends', () => {
  const { from, to } = ndDateRange.presetRange('yesterday', BASE);
  assert.equal(ndDateRange.formatDate(from), '2026-07-03');
  assert.equal(ndDateRange.formatDate(to), '2026-07-03');
});

test('presetRange__a_name_it_does_not_know__returns_null', () => {
  assert.equal(ndDateRange.presetRange('all', BASE), null);
  assert.equal(ndDateRange.presetRange('custom', BASE), null);
});

test('parseRange__the_wire_format__gives_both_dates', () => {
  assert.deepEqual(ndDateRange.parseRange('1970-01-01 to 2026-09-07'), ['1970-01-01', '2026-09-07']);
});

test('parseRange__an_empty_field__gives_nothing', () => {
  assert.deepEqual(ndDateRange.parseRange(''), []);
});
