// Guards hideWithTooltip() in share/public/javascripts/netdisco.js.
//
// netdisco#1667: clicking the ports filter's bin clears the field, which hides
// the bin, while the bin's own tooltip is showing. Bootstrap dismisses a tip
// when the pointer leaves its trigger. macOS Chrome fires no boundary event
// when the trigger is hidden under a pointer that has not moved, so the tip is
// never dismissed and popper anchors it to a zero sized rectangle, which puts
// it at the window origin. Captured in the browser as:
//
//   {"text":"Show all Ports","at":"0,6","owner":"f_clear_btn","ownerHidden":true}
//
// WHY THIS IS NOT A BROWSER TEST. Linux Chromium and Firefox both fire the
// event, so they dismiss the tip correctly and a browser assertion passes
// against a build with the fix removed. That was measured, not assumed: a
// Playwright reproduction written for this issue stayed green after the
// dismissal was deliberately disabled. CI and the visual harness are both
// Linux Chromium, so neither can hold this line.
//
// So the property asserted here is that the code does not depend on the event
// at all: it disposes the tooltip itself, before hiding, for the element and
// for any tooltip carrying element inside it. The helper is extracted from the
// shipped file and executed, so a reordering or a dropped dispose fails here.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const SOURCE = path.join(__dirname, '..', '..', 'share', 'public', 'javascripts', 'netdisco.js');
const source = fs.readFileSync(SOURCE, 'utf8');

// Take the shipped function text rather than a copy of it, so this cannot pass
// against a helper that no longer says what the copy said.
function extract(name) {
  const start = source.indexOf('function ' + name + ' (');
  const alt = source.indexOf('function ' + name + '(');
  const from = start === -1 ? alt : start;
  assert.notStrictEqual(from, -1, name + ' is not defined in netdisco.js');
  let depth = 0, i = source.indexOf('{', from);
  for (let j = i; j < source.length; j += 1) {
    if (source[j] === '{') depth += 1;
    if (source[j] === '}') { depth -= 1; if (depth === 0) return source.slice(from, j + 1); }
  }
  throw new Error('unbalanced braces in ' + name);
}

// A jQuery stand-in holding only what the helper uses. Every call is recorded
// so the ORDER of dispose against hide can be asserted, which is the whole
// point: disposing after the hide would leave the tip on screen just as surely
// as not disposing at all.
function harness({ selfIsTooltip = false, descendants = [], withInstance = () => true } = {}) {
  const calls = [];
  const node = { id: 'f_clear_btn', __tip: selfIsTooltip };
  const set = (members) => ({
    members,
    find: (sel) => { assert.strictEqual(sel, '[rel=tooltip]'); return set(descendants); },
    addBack: (sel) => { assert.strictEqual(sel, '[rel=tooltip]');
                        return set(members.concat(node.__tip ? [node] : [])); },
    each: function (fn) { members.forEach((m) => fn.call(m)); return this; },
    hide: () => { calls.push('hide'); },
  });
  const $ = () => set([node]);
  const bootstrap = { Tooltip: { getInstance: (el) => (withInstance(el)
    ? { dispose: () => calls.push('dispose:' + (el.name || el.id)) } : null) } };
  const fn = new Function('$', 'bootstrap', extract('hideWithTooltip') + '; return hideWithTooltip;')($, bootstrap);
  return { fn, calls };
}

test('hideWithTooltip__the_element_carries_a_tooltip__disposes_it_before_hiding', () => {
  const { fn, calls } = harness({ selfIsTooltip: true });
  fn('#f_clear_btn');
  assert.deepStrictEqual(calls, ['dispose:f_clear_btn', 'hide'],
    'the tooltip must be disposed first; disposing after the hide strands it just the same');
});

test('hideWithTooltip__a_tooltip_is_inside_the_element__disposes_the_descendant', () => {
  const inner = { name: 'nd_sidebar-pin' };
  const { fn, calls } = harness({ descendants: [inner] });
  fn('.nd_sidebar');
  assert.deepStrictEqual(calls, ['dispose:nd_sidebar-pin', 'hide'],
    'hiding a container must dismiss the tooltips of what it contains');
});

test('hideWithTooltip__no_tooltip_has_been_shown_yet__still_hides', () => {
  const { fn, calls } = harness({ selfIsTooltip: true, withInstance: () => false });
  fn('#f_clear_btn');
  assert.deepStrictEqual(calls, ['hide'],
    'bootstrap builds an instance on first hover, so there is often none to dispose');
});

// The two call sites. A helper nothing calls fixes nothing, and both of these
// hide an element that can be carrying a tooltip at the time.
test('netdiscoJs__every_hide_of_a_tooltip_carrier__goes_through_the_helper', () => {
  assert.match(source, /hideWithTooltip\(id\);/,
    "device_form_state must hide the field's clear icon through the helper");
  assert.match(source, /hideWithTooltip\('\.nd_sidebar, #nd_sidebar-toggle-img-out'\);/,
    'nd_apply_sidebar must hide the sidebar through the helper');
  assert.doesNotMatch(source, /\$\(id\)\.hide\(\)/,
    'a bare hide of the clear icon is the #1667 defect');
  assert.doesNotMatch(source, /\$\('\.nd_sidebar, #nd_sidebar-toggle-img-out'\)\.hide\(\)/,
    'a bare hide of the sidebar strands the tooltips of its chrome icons');
});
