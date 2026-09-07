// Guards destroyAutocompletesIn and its call from the handler that empties a
// pane.
//
// Not a source text test, deliberately. Both things that matter are about what
// runs: every widget in the outgoing pane has to be reached, and it has to
// happen before the empty, after which the fields are gone and their instances
// cannot be found. So the shipped function and the shipped listener are
// extracted and executed against stubs rather than read.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const source = fs.readFileSync(
  path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco.js'), 'utf8');

// Take the shipped function text rather than a copy of it, so this cannot pass
// against a helper that no longer says what the copy said.
function braceMatch(from) {
  let depth = 0;
  for (let j = source.indexOf('{', from); j < source.length; j += 1) {
    if (source[j] === '{') depth += 1;
    if (source[j] === '}') { depth -= 1; if (depth === 0) return source.slice(from, j + 1); }
  }
  throw new Error('unbalanced braces from offset ' + from);
}

function extract(name) {
  const from = source.search(new RegExp('function\\s+' + name + '\\s*\\('));
  assert.notStrictEqual(from, -1, name + ' is not defined in netdisco.js');
  return braceMatch(from);
}

// The listener is anonymous, so the event name is the only anchor.
function extractListener(event) {
  const anchor = source.indexOf("document.body.addEventListener('" + event + "'");
  assert.notStrictEqual(anchor, -1, 'no listener for ' + event + ' in netdisco.js');
  const from = source.indexOf('function', anchor);
  return braceMatch(from);
}

// --- stubs -----------------------------------------------------------------

// A field the widget never took over answers undefined to 'instance', and
// throws for every other method name.
function field(name, initialized, calls) {
  return { name: name,
           __widget: initialized
             ? { destroy: function () { calls.push('destroy:' + name) } }
             : undefined };
}

function pane(id, fields, calls) {
  return {
    id: id,
    querySelectorAll: function (selector) {
      calls.push('query:' + selector);
      return fields;
    },
    set innerHTML(value) { calls.push('innerHTML=' + JSON.stringify(value)) },
    get innerHTML() { return '' },
  };
}

function jquery() {
  return function (element) {
    return { autocomplete: function (method) {
      assert.strictEqual(method, 'instance',
        'any other method name throws on a field that was never initialized');
      return element.__widget;
    } };
  };
}

function teardown() {
  return new Function('$', extract('destroyAutocompletesIn')
    + '; return destroyAutocompletesIn;')(jquery());
}

function beforeRequest() {
  return new Function('window', '$',
    extract('destroyAutocompletesIn')
    + '; return ' + extractListener('htmx:beforeRequest') + ';')({}, jquery());
}

// --- the helper ------------------------------------------------------------

test('destroyAutocompletesIn__the_pane_holds_initialized_fields__destroys_every_one', () => {
  const calls = [];
  const fields = [field('dev1', true, calls), field('port1', true, calls),
                  field('dev2', true, calls), field('port2', true, calls)];
  teardown()(pane('topology_pane', fields, calls));
  assert.deepStrictEqual(calls.filter((c) => c.startsWith('destroy:')),
    ['destroy:dev1', 'destroy:port1', 'destroy:dev2', 'destroy:port2'],
    'one widget left behind is one suggestion list and one live region left in the body');
});

test('destroyAutocompletesIn__the_widget_is_found_by_the_jquery_ui_class__not_by_our_selectors', () => {
  const calls = [];
  teardown()(pane('acleditor_pane', [field('left_rule', true, calls)], calls));
  assert.deepStrictEqual(calls[0], 'query:.ui-autocomplete-input',
    'jQuery UI marks a field it has taken over, so a site-local field is covered too');
  const body = extract('destroyAutocompletesIn');
  assert.ok(!/nd_[\w-]+/.test(body),
    'naming netdisco selectors here would miss any field added later');
});

test('destroyAutocompletesIn__a_field_was_never_initialized__leaves_it_alone', () => {
  const calls = [];
  const fields = [field('plain', false, calls), field('typeahead', true, calls)];
  teardown()(pane('jobqueue_pane', fields, calls));
  assert.deepStrictEqual(calls.filter((c) => c.startsWith('destroy:')), ['destroy:typeahead']);
});

test('destroyAutocompletesIn__the_pane_holds_no_fields__does_nothing', () => {
  const calls = [];
  teardown()(pane('netmap_pane', [], calls));
  assert.deepStrictEqual(calls, ['query:.ui-autocomplete-input']);
});

test('destroyAutocompletesIn__there_is_no_pane__does_nothing', () => {
  assert.doesNotThrow(() => { teardown()(null) });
  assert.doesNotThrow(() => { teardown()(undefined) });
});

// --- the listener ----------------------------------------------------------

test('htmxBeforeRequest__a_pane_with_autocomplete_fields__destroys_them_before_emptying', () => {
  const calls = [];
  const fields = [field('dev1', true, calls), field('port1', true, calls)];
  const target = pane('topology_pane', fields, calls);
  beforeRequest()({ detail: { target: target } });
  assert.deepStrictEqual(calls,
    ['query:.ui-autocomplete-input', 'destroy:dev1', 'destroy:port1', 'innerHTML=""'],
    'after the empty the fields are gone and their widgets can no longer be reached');
});

test('htmxBeforeRequest__the_jobqueue_pane__is_left_untouched', () => {
  const calls = [];
  const target = pane('jobqueue_pane', [field('backend', true, calls)], calls);
  beforeRequest()({ detail: { target: target } });
  assert.deepStrictEqual(calls, [],
    'it refreshes on a timer and is not emptied, so nothing in it is on its way out here');
});

test('htmxBeforeRequest__a_target_that_is_not_a_pane__is_left_untouched', () => {
  const calls = [];
  const target = pane('nd_nodes_box', [field('anything', true, calls)], calls);
  beforeRequest()({ detail: { target: target } });
  assert.deepStrictEqual(calls, []);
});
