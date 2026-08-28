// With autosave on, the map must be posted once per settle and once per drag,
// never once per mouse movement.
//
// force-graph reheats the simulation on every drag event. Once the first
// layout has finished, alpha is already below d3AlphaMin, so the engine stops
// again immediately having run no ticks at all. Hanging the save off
// onEngineStop therefore fires it once per mousemove. Measured on this branch
// before the fix, against a 6493 device database: a drag of 4 mouse movements
// produced 4 posts, 12 produced 12, and 24 produced 24, each carrying the whole
// map at 327131 bytes on the 6481 node map. Replacing onEngineStop with a bare
// counter gave 12 engine stops and 0 posts, which is what pins the trigger on
// it. The old d3 renderer produced none for the same drag.
//
// So two things are needed together. A tick count tells a real settle apart
// from a stop that did no work, and onNodeDragEnd is what persists a node the
// user moved by hand, since the stop that follows a drag runs no ticks.
//
// A success handler here only runs at all because the route sets its own
// content type. It used to inherit Dancer::Plugin::Ajax's text/xml default and
// answer with a stringified DBIC row, which jQuery rejected as invalid XML on a
// 200, so the first version of this toast was correct by every source test and
// never appeared. That is asserted on the server side in
// xt/36-ajax-content-response.t; do not reintroduce a dataType override here to
// paper over it if the route ever regresses.
//
// The same distinction decides who gets told. With autosave on the map saves
// itself at every settle and every drag, so a toast for each would be noise.
// The sidebar Save button is the one case where the user asked for a save and
// has nothing else to confirm it happened, so it announces, and only when
// autosave is off.

'use strict';

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');
const netmapJs = () => fs.readFileSync(
  path.join(repoRoot, 'share', 'views', 'js', 'netmap.js'), 'utf8');
const deviceJs = () => fs.readFileSync(
  path.join(repoRoot, 'share', 'views', 'js', 'device.js'), 'utf8');

// balanced to the handler's own closing paren, so an assertion cannot pass by
// matching text that belongs to a different handler. A line-indent heuristic
// was tried first and cut the onEngineStop body at its own fg.graphData() call.
const handlerBody = (src, name) => {
  const at = src.indexOf('.' + name + '(');
  assert.notEqual(at, -1, `netmap.js must register ${name}`);
  const open = src.indexOf('(', at);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '(') { depth++ }
    else if (src[i] === ')') { depth--; if (depth === 0) { return src.slice(open, i + 1) } }
  }
  assert.fail(`unbalanced parentheses after ${name} in netmap.js`);
};

describe('netmap autosave', () => {
  test('engineTick__while_the_simulation_runs__increments_a_counter', () => {
    const body = handlerBody(netmapJs(), 'onEngineTick');
    assert.match(
      body,
      /\+\+/,
      'the tick handler must count, or there is no way to tell a settle from an engine ' +
      'stop that ran nothing, and force-graph produces one of those per drag event. ' +
      'Count inside the existing handler: onEngineTick is a setter, so registering a ' +
      'second one would silently replace the spinner reset'
    );
  });

  test('engineStop__having_run_no_ticks__does_not_post_the_map', () => {
    const body = handlerBody(netmapJs(), 'onEngineStop');
    assert.match(
      body,
      /saveMapPositions/,
      'the settle after the first layout is still what saves it'
    );
    assert.match(
      body,
      /ticks[\s\S]{0,300}?saveMapPositions/i,
      'the save in onEngineStop must be guarded by the tick count, or every drag event ' +
      'posts the whole map again'
    );
  });

  test('nodeDragEnd__with_autosave_on__posts_the_map_once', () => {
    const body = handlerBody(netmapJs(), 'onNodeDragEnd');
    assert.match(
      body,
      /saveMapPositions/,
      'the engine stop after a drag runs no ticks, so without a save here a node the ' +
      'user moved by hand is never persisted. That was the old renderer\'s behavior ' +
      'and it is not worth reproducing'
    );
  });
});

describe('netmap manual save', () => {
  test('saveMapPositions__called_by_the_button_with_autosave_off__announces', () => {
    const src = netmapJs();
    const at = src.indexOf('saveMapPositions = function');
    assert.notEqual(at, -1, 'netmap.js must define saveMapPositions');
    const body = src.slice(at, src.indexOf('\n  };', at));
    assert.match(
      body,
      /toastr\.success/,
      'a manual save has nothing else to confirm it happened, so it must say so'
    );
    assert.match(
      body,
      /if\s*\([^)]*!\s*autosaveOn[^)]*\)[\s\S]{0,120}?toastr\.success/,
      'the toast must be suppressed when autosave is on, or the map announces itself ' +
      'at every settle and every drag'
    );
    assert.match(
      body,
      /function\s*\(\s*\w+\s*\)/,
      'saveMapPositions must take the caller\'s intent as an argument: the autosave ' +
      'calls and the button call are otherwise indistinguishable from inside it'
    );
  });

  test('saveButton__on_click__tells_saveMapPositions_it_was_the_user', () => {
    const src = deviceJs();
    const at = src.indexOf("'#nd_netmap-save'");
    assert.notEqual(at, -1, 'device.js must bind the netmap Save button');
    const handler = src.slice(at, at + 260);
    assert.match(
      handler,
      /saveMapPositions\(\s*\w+/,
      'the button must pass an argument, or netmap.js cannot tell a click from the ' +
      'saves autosave makes on its own'
    );
  });
});
