// Guards removeStrandedPopovers in netdisco.js. The race that strands a tip
// cannot be scheduled, so the contract is asserted instead: a tip whose trigger
// has gone is removed, one whose trigger is still there is left alone.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', '..', 'share', 'public', 'javascripts', 'netdisco.js'), 'utf8');

// Take the shipped function text rather than a copy of it.
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

// One tip, and whatever the page holds that describes it.
function page({ id, describedBy }) {
  const removed = [];
  const tip = { id, remove: () => removed.push(id) };
  const document = {
    querySelectorAll: () => [tip],
    querySelector: (selector) =>
      (describedBy && selector === '[aria-describedby="' + describedBy + '"]' ? {} : null),
  };
  // eslint-disable-next-line no-new-func
  new Function('document', extract('removeStrandedPopovers') + '; removeStrandedPopovers();')(document);
  return removed;
}

test('strandedPopover__its_trigger_gone_from_the_page__is_removed', () => {
  assert.deepStrictEqual(page({ id: 'tip1', describedBy: null }), ['tip1']);
});

test('strandedPopover__its_trigger_still_there__is_left_alone', () => {
  assert.deepStrictEqual(page({ id: 'tip1', describedBy: 'tip1' }), []);
});

// The id is what matches a tip back to its trigger; without one it cannot be.
test('strandedPopover__a_tip_with_no_id__is_removed', () => {
  assert.deepStrictEqual(page({ id: '', describedBy: null }), ['']);
});
