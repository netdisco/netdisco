// Guards hideWithTooltip() in share/public/javascripts/netdisco.js, and the
// rule that nothing else hides an element which may be showing a tooltip.
//
// netdisco#1667: clicking the ports filter's bin clears the field, which hides
// the bin, while the bin's own tooltip is showing. Bootstrap dismisses a tip
// when the pointer leaves its trigger. macOS Chrome fires no boundary event
// when the trigger is hidden under a pointer that has not moved, so the tip is
// never dismissed and popper anchors it to a zero sized rectangle, which puts
// it at the window origin. Captured in the browser:
//
//   {"text":"Show all Ports","at":"0,6","owner":"f_clear_btn","ownerHidden":true}
//
// WHY THIS IS NOT A BROWSER TEST. Linux Chromium and Firefox both fire the
// event, so they dismiss the tip correctly and a browser assertion passes
// against a build with the fix removed. That was measured, not assumed: a
// Playwright reproduction written for this issue stayed green after the
// dismissal was deliberately disabled. CI and the visual harness are both
// Linux Chromium, so neither can catch this regressing.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const NETDISCO_JS = path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco.js');
const source = fs.readFileSync(NETDISCO_JS, 'utf8');

// --- the helper itself -----------------------------------------------------

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

// A jQuery stand-in holding only what the helper uses. Every call is recorded
// so the ORDER of dispose against hide can be asserted, which is the point:
// disposing after the hide strands the tip just as surely as not disposing.
function harness({ selfIsTooltip = false, descendants = [], withInstance = () => true } = {}) {
  const calls = [];
  const node = { id: 'f_clear_btn', __tip: selfIsTooltip };
  const set = (members) => ({
    find: (sel) => { assert.strictEqual(sel, '[rel=tooltip]'); return set(descendants); },
    addBack: (sel) => { assert.strictEqual(sel, '[rel=tooltip]');
                        return set(members.concat(node.__tip ? [node] : [])); },
    each: function (fn) { members.forEach((m) => fn.call(m)); return this; },
    hide: () => { calls.push('hide'); },
  });
  const $ = () => set([node]);
  const bootstrap = { Tooltip: { getInstance: (el) => (withInstance(el)
    ? { dispose: () => calls.push('dispose:' + (el.name || el.id)) } : null) } };
  const fn = new Function('$', 'bootstrap',
    extract('hideWithTooltip') + '; return hideWithTooltip;')($, bootstrap);
  return { fn, calls };
}

test('hideWithTooltip__the_element_carries_a_tooltip__disposes_it_before_hiding', () => {
  const { fn, calls } = harness({ selfIsTooltip: true });
  fn('#f_clear_btn');
  assert.deepStrictEqual(calls, ['dispose:f_clear_btn', 'hide'],
    'the tooltip must be disposed first; disposing after the hide strands it just the same');
});

test('hideWithTooltip__a_tooltip_is_inside_the_element__disposes_the_descendant', () => {
  const { fn, calls } = harness({ descendants: [{ name: 'nd_sidebar-pin' }] });
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

// --- the rule --------------------------------------------------------------
//
// A helper only two call sites use fixes only two call sites. This reads the
// templates for every element carrying rel="tooltip", adds the elements that
// CONTAIN one (hiding a wrapper hides its children), and then refuses a bare
// .hide() naming any of them.
//
// Scoped to ids and nd_ prefixed classes. Bootstrap utility classes such as
// form-control also appear on tooltip carriers, and matching those would flag
// any hide anywhere for no gain.

const TAG = /<(\/?)([a-zA-Z][\w-]*)([^<>]*?)(\/?)>/gs;
const ATTR = /([\w-]+)\s*=\s*"([^"]*)"/gs;
const VOID = new Set(['br', 'hr', 'img', 'input', 'link', 'meta', 'source',
                      'col', 'area', 'base', 'embed', 'wbr']);

function selectorsOf(attrs) {
  const out = [];
  if (attrs.id && !attrs.id.includes('[%')) out.push('#' + attrs.id.trim());
  const classes = (attrs.class || '').replace(/\[%.*?%\]/gs, ' ');
  for (const c of classes.split(/\s+/)) if (c.startsWith('nd_')) out.push('.' + c);
  return out;
}

function walk(dir, ext, found = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, ext, found);
    else if (entry.name.endsWith(ext)) found.push(full);
  }
  return found;
}

function riskySelectors() {
  const risky = new Map();
  for (const file of walk(path.join(ROOT, 'share', 'views'), '.tt')) {
    const text = fs.readFileSync(file, 'utf8');
    const stack = [];
    for (const m of text.matchAll(TAG)) {
      const [, closing, name, rest, selfClose] = m;
      if (closing) {
        while (stack.length && stack.pop().name !== name.toLowerCase()) { /* unbalanced TT */ }
        continue;
      }
      const attrs = Object.fromEntries([...rest.matchAll(ATTR)].map((a) => [a[1], a[2]]));
      const own = selectorsOf(attrs);
      if (attrs.rel === 'tooltip') {
        for (const s of own) if (!risky.has(s)) risky.set(s, 'carries a tooltip');
        for (const anc of stack) {
          for (const s of anc.own) if (!risky.has(s)) risky.set(s, 'contains a tooltip');
        }
      }
      if (!VOID.has(name.toLowerCase()) && !selfClose) stack.push({ name: name.toLowerCase(), own });
    }
  }
  return risky;
}

// Our own JavaScript. The vendored libraries under share/public/javascripts/
// are excluded: they hide their own elements constantly and none of them knows
// about netdisco's markup.
function ourScripts() {
  const pub = path.join(ROOT, 'share', 'public', 'javascripts');
  return fs.readdirSync(pub).filter((f) => /^netdisco.*\.js$/.test(f)).map((f) => path.join(pub, f))
    .concat(walk(path.join(ROOT, 'share', 'views', 'js'), '.js'));
}

// A detector that cannot fire reports zero for the same reason a working one
// reports zero against clean code. If the harvest breaks, this fails first.
test('tooltipHarvest__the_templates__yield_the_known_carriers', () => {
  const risky = riskySelectors();
  assert.ok(risky.size > 10, 'expected many tooltip carriers, found ' + risky.size);
  assert.strictEqual(risky.get('#f_clear_btn'), 'carries a tooltip');
  assert.strictEqual(risky.get('#nd_csv-download'), 'contains a tooltip');
});

test('ourJavaScript__hiding_anything_that_can_show_a_tooltip__uses_the_helper', () => {
  const risky = riskySelectors();
  const offenders = [];
  for (const file of ourScripts()) {
    const lines = fs.readFileSync(file, 'utf8').split('\n');
    lines.forEach((line, i) => {
      if (!line.includes('.hide()') || line.includes('hideWithTooltip')) return;
      const literals = [...line.matchAll(/(['"])([^'"]+)\1/g)].map((m) => m[2]);
      for (const sel of risky.keys()) {
        if (literals.some((lit) => lit.includes(sel))) {
          offenders.push(path.relative(ROOT, file) + ':' + (i + 1) + '  ' + line.trim()
            + '   [' + sel + ' ' + risky.get(sel) + ']');
          return;
        }
      }
    });
  }
  assert.deepStrictEqual(offenders, [],
    'these hide an element that can be showing a tooltip; use hideWithTooltip() so the '
    + 'tip is dismissed rather than left anchored to something invisible');
});
