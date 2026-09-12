// Guards the double-click gesture on an SNMP tree label in
// share/public/javascripts/netdisco.js: the dblclick listener that toggles the
// row's branch, and the capture-phase click listener that keeps the pair of
// clicks to one panel request.
//
// The listeners are run, not matched, so this cannot pass against a rewrite
// that keeps the shape and loses the behaviour. Which element htmx's own
// handler is bound to is a browser question, and the harness spec
// interact-snmp-tree.spec.js asks it there.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', '..', 'share', 'public', 'javascripts', 'netdisco.js'), 'utf8');

// Take the shipped listener text rather than a copy of it.
function registration(type) {
  const at = source.indexOf("document.body.addEventListener('" + type + "', function (evt) {");
  assert.notStrictEqual(at, -1, 'netdisco.js registers no ' + type + ' listener on document.body');
  const open = source.indexOf('{', source.indexOf('function (evt)', at));
  let depth = 0;
  for (let j = open; j < source.length; j += 1) {
    if (source[j] === '{') depth += 1;
    if (source[j] === '}') {
      depth -= 1;
      if (depth === 0) {
        return { body: source.slice(open + 1, j), tail: source.slice(j + 1, source.indexOf(')', j) + 1) };
      }
    }
  }
  throw new Error('unbalanced braces in the ' + type + ' listener');
}

// One row of the tree: a label, and for a branch a details beside it.
function row({ branch = true, open = false } = {}) {
  const details = branch ? { open } : null;
  const element = {
    closest: (sel) => (sel === '.nd_snmp-row' ? element : null),
    querySelector: (sel) => (sel === ':scope > details' ? details : null),
  };
  const label = { closest: (sel) => (sel === 'a.nd_snmp-label' ? label : element.closest(sel)) };
  return { label, details };
}

function dispatch(type, target, detail) {
  const { body } = registration(type);
  const calls = [];
  // eslint-disable-next-line no-new-func
  new Function('evt', body)({
    target,
    detail,
    stopPropagation: () => calls.push('stopPropagation'),
    preventDefault: () => calls.push('preventDefault'),
  });
  return calls;
}

test('snmpTreeLabel__double_clicked__opens_the_branch_on_its_row', () => {
  const { label, details } = row();
  dispatch('dblclick', label);
  assert.strictEqual(details.open, true);
});

test('snmpTreeLabel__double_clicked_while_open__closes_the_branch', () => {
  const { label, details } = row({ open: true });
  dispatch('dblclick', label);
  assert.strictEqual(details.open, false);
});

test('snmpTreeLeaf__double_clicked__has_nothing_to_toggle', () => {
  const { label } = row({ branch: false });
  assert.doesNotThrow(() => dispatch('dblclick', label));
});

test('snmpTree__double_clicking_away_from_a_label__is_left_alone', () => {
  const elsewhere = { closest: () => null };
  assert.doesNotThrow(() => dispatch('dblclick', elsewhere));
});

test('snmpTreeLabel__second_click_of_a_pair__does_not_ask_for_the_panel_again', () => {
  const { label } = row();
  assert.deepStrictEqual(dispatch('click', label, 2), ['stopPropagation', 'preventDefault']);
});

test('snmpTreeLabel__a_single_click__still_reaches_htmx', () => {
  const { label } = row();
  assert.deepStrictEqual(dispatch('click', label, 1), []);
});

// htmx binds its handler on the anchor itself, so the suppression above only
// runs first if it is registered for the capture phase.
test('snmpTreeLabel__the_click_suppression__runs_before_the_anchors_own_handler', () => {
  assert.match(registration('click').tail, /,\s*true\s*\)/,
    'the click listener is no longer registered in the capture phase');
});
