// The netmap pane must say something while it waits for its first paint.
//
// netdisco.js's do_search shows "Waiting for results..." only while it fetches
// /ajax/content/device/netmap. That fragment is about 500 bytes and arrives in
// a few milliseconds, and the moment it does, $(target).html(content) replaces
// the message. The wait the user actually experiences is the one after that:
// the fragment's own $.getJSON to /ajax/data/device/netmap, then parsing the
// payload, then the first force layout. Measured against a 6481 node network
// that is 4.8MB over about a second, plus layout, with nothing on screen.
//
// So the fragment carries its own indicator, and the data callback removes it.
// The wrap also needs a height of its own: until ForceGraph sizes the
// container, the wrap's only in-flow child is empty, so it collapses to zero
// height and the absolutely positioned spinner and fullscreen control resolve
// against a box with no room, landing above the pane instead of inside it.

'use strict';

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');
const read = (...parts) => fs.readFileSync(path.join(repoRoot, ...parts), 'utf8');

const LOADING_ID = 'nd2_netmap-loading';

describe('netmap first paint indicator', () => {
  test('fragment__before_the_data_arrives__ships_a_loading_indicator', () => {
    const fragment = read('share', 'views', 'ajax', 'device', 'netmap.tt');
    assert.match(
      fragment,
      new RegExp(`id="${LOADING_ID}"`),
      `share/views/ajax/device/netmap.tt must carry an element with id "${LOADING_ID}", ` +
      'or the pane is blank for the whole data request and first layout'
    );
    assert.match(
      fragment,
      /fa-spinner fa-spin/,
      'the indicator must use the same spinner glyph as netdisco.js\'s "Waiting for results..." ' +
      'so the netmap pane does not announce a slow load differently from every other tab'
    );
  });

  test('dataCallback__once_the_graph_is_built__removes_the_loading_indicator', () => {
    const js = read('share', 'views', 'js', 'netmap.js');
    assert.match(
      js,
      new RegExp(LOADING_ID),
      `share/views/js/netmap.js must reference "${LOADING_ID}"`
    );
    assert.match(
      js,
      new RegExp(`${LOADING_ID}[\\s\\S]{0,200}?\\.remove\\(\\)`),
      `share/views/js/netmap.js must remove "${LOADING_ID}", or it stays on top of the map`
    );
  });

  // Reproduced 2026-08-30 by re-submitting the netmap sidebar form: the pane is
  // replaced while the previous instance is still running, and nothing destroys
  // it until the next fragment's data callback, so its handlers fire against a
  // spinner that has left the document.
  test('spinnerHandlers__pane_replaced_mid_run__do_not_dereference_a_missing_element', () => {
    const js = read('share', 'views', 'js', 'netmap.js');
    assert.doesNotMatch(
      js,
      /getElementById\(['"]nd2_netmap-spinner['"]\)\s*\./,
      'share/views/js/netmap.js must not read a property straight off the spinner lookup: ' +
      'onEngineTick and onEngineStop both outlive the element on a reload in place, ' +
      'and an unguarded read throws a TypeError into the console on every re-submit'
    );
  });

  test('wrap__before_the_canvas_exists__has_a_height_of_its_own', () => {
    const css = read('share', 'public', 'css', 'netdisco.css');
    const rule = css.match(/#nd2_netmap-wrap\s*\{[^}]*\}/);
    assert.ok(rule, 'netdisco.css must carry a #nd2_netmap-wrap rule');
    assert.match(
      rule[0],
      /min-height/,
      'without a min-height the wrap collapses until ForceGraph sizes the container, ' +
      'so the spinner and fullscreen control render above the pane rather than in it'
    );
  });
});
