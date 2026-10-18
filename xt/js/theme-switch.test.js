// Guards the user menu's light / computer / dark switch, shown when web_theme
// is auto. The resolver (theme-resolver.test.js) owns saving and applying a
// choice; this file checks that the switch hands clicks to it, shows which
// choice is on, and keeps the menu open.
//
// Bootstrap closes a dropdown on any click inside its menu unless the target
// is a form field, and it listens on document. The switch stops the click
// before it gets there, so the user sees the theme change with the menu still
// open.

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', '..', 'share', 'public', 'javascripts', 'netdisco.js'), 'utf8');

function extract(name) {
  const from = source.indexOf('function ' + name);
  if (from < 0) throw new Error('no function ' + name + ' in netdisco.js');
  let depth = 0;
  for (let j = source.indexOf('{', from); j < source.length; j += 1) {
    if (source[j] === '{') depth += 1;
    if (source[j] === '}') { depth -= 1; if (depth === 0) return source.slice(from, j + 1); }
  }
  throw new Error('unbalanced braces in ' + name);
}

const initSwitch = new Function(
  extract('nd_init_theme_switch') + '; return nd_init_theme_switch;')();

function button(choice) {
  const classes = new Set();
  const attrs = {};
  return {
    dataset: { ndThemeChoice: choice },
    classList: { toggle: (c, on) => { if (on) classes.add(c); else classes.delete(c); } },
    setAttribute: (k, v) => { attrs[k] = String(v); },
    closest: function (sel) { return sel === 'button[data-nd-theme-choice]' ? this : null; },
    active: () => classes.has('active'),
    pressed: () => attrs['aria-pressed'],
  };
}

function setup(initial) {
  const buttons = ['light', 'auto', 'dark'].map(button);
  const listeners = {};
  const sw = {
    querySelectorAll: (sel) => (sel === 'button[data-nd-theme-choice]' ? buttons : []),
    addEventListener: (type, fn) => { listeners[type] = fn; },
  };
  const calls = [];
  let current = initial;
  const theme = {
    choose: (name) => { calls.push(name); current = name; },
    chosen: () => current,
  };
  initSwitch(sw, theme);
  const click = (target) => {
    const event = { target, stopped: false, stopPropagation() { this.stopped = true; } };
    listeners.click(event);
    return event;
  };
  const on = () => buttons.filter((b) => b.active()).map((b) => b.dataset.ndThemeChoice);
  return { buttons, calls, click, on };
}

test('themeSwitch__on_load__marks_the_saved_choice', () => {
  const s = setup('dark');
  assert.deepEqual(s.on(), ['dark']);
  assert.deepEqual(s.buttons.map((b) => b.pressed()), ['false', 'false', 'true']);
});

test('themeSwitch__with_nothing_saved__marks_computer', () => {
  assert.deepEqual(setup('auto').on(), ['auto']);
});

test('themeSwitch__clicking_a_button__chooses_it_and_moves_the_mark', () => {
  const s = setup('auto');
  s.click(s.buttons[0]);
  assert.deepEqual(s.calls, ['light']);
  assert.deepEqual(s.on(), ['light']);
  assert.deepEqual(s.buttons.map((b) => b.pressed()), ['true', 'false', 'false']);
});

test('themeSwitch__clicking_a_button__keeps_the_menu_open', () => {
  const s = setup('auto');
  assert.equal(s.click(s.buttons[2]).stopped, true);
});

// The icon inside a button is the usual click target.
test('themeSwitch__clicking_the_icon__chooses_its_button', () => {
  const s = setup('auto');
  s.click({ closest: (sel) => (sel === 'button[data-nd-theme-choice]' ? s.buttons[2] : null) });
  assert.deepEqual(s.calls, ['dark']);
});

test('themeSwitch__clicking_between_buttons__chooses_nothing_and_keeps_the_menu_open', () => {
  const s = setup('auto');
  const event = s.click({ closest: () => null });
  assert.deepEqual(s.calls, []);
  assert.equal(event.stopped, true);
});
