// The colorby=hgroup / colorby=lgroup legend must stay inside the map.
//
// Its rows are the distinct COLORVALUEs of the rendered nodes, and for
// colorby=lgroup that is the raw device.location string
// (Web/Plugin/Device/Neighbors.pm:273). Neither the row count nor the string
// length is bounded by anything. Measured live against a 6493 device network
// with mapshow=all: 3152 rows, longest label 184 characters, which unbounded
// renders as a box 1099px wide and 56748px tall against a map wrap of 800px.
// The box is absolutely positioned, so it does not expand the wrap; it spills
// down the document instead, and the canvas ends while the legend keeps going.
//
// The old d3 renderer drew its legend inside the SVG
// (d3-force-network-chart.js, createLegend), so overflow was clipped rather
// than pushed onto the page, and it sorted its rows. Containment and ordering
// are therefore parity, not new behavior.
//
// Rows clip to one line rather than wrapping. Wrapping hides nothing, but 46%
// of these labels exceed the ~42 characters that fit on a line, which made the
// list 100524px instead of 56748px. The title attribute is what makes the
// clipping safe: 28% of labels are not uniquely identified by their visible
// first 42 characters, because the underscore-joined site codes share long
// prefixes, so those rows are distinguishable only on hover.

'use strict';

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');
const read = (...parts) => fs.readFileSync(path.join(repoRoot, ...parts), 'utf8');

const cssRule = (selector) => {
  const css = read('share', 'public', 'css', 'netdisco.css');
  const rule = css.match(new RegExp(`${selector}\\s*\\{[^}]*\\}`));
  assert.ok(rule, `netdisco.css must carry a ${selector} rule`);
  return rule[0];
};

describe('netmap legend containment', () => {
  test('legend__with_more_rows_than_the_map_is_tall__is_capped_and_scrolls', () => {
    const rule = cssRule('#nd2_netmap-legend');
    assert.match(
      rule,
      /max-height:\s*calc\(100%/,
      'the legend must cap against its own containing block, the map wrap, so that a ' +
      '3152 row legend cannot run past the bottom of the canvas. A viewport unit would ' +
      'drift from the wrap once the pane goes fullscreen'
    );
    assert.match(
      rule,
      /overflow-y:\s*auto/,
      'capped without a scroller the extra rows are simply unreachable, which is the ' +
      'clipping behavior of the old SVG legend rather than a fix for it'
    );
    assert.match(
      rule,
      /max-width:/,
      'without a max-width one 184 character location makes the legend wider than half ' +
      'the viewport, hiding the map underneath it'
    );
  });

  test('legendRow__with_a_label_wider_than_the_box__clips_to_one_line', () => {
    const rule = cssRule('#nd2_netmap-legend div');
    assert.match(
      rule,
      /white-space:\s*nowrap/,
      'rows must stay on one line. Wrapping these labels made the list 100524px rather ' +
      'than 56748px, because 46% of them are longer than a line'
    );
    assert.match(
      rule,
      /text-overflow:\s*ellipsis/,
      'a clipped row must say it is clipped, or a truncated location reads as the whole ' +
      'location'
    );
    assert.match(
      rule,
      /overflow:\s*hidden/,
      'text-overflow does nothing without it: the row would simply spill past the box'
    );
  });

  test('legendRow__built_from_a_color_key__carries_the_full_label_as_a_title', () => {
    const js = read('share', 'views', 'js', 'netmap.js');
    const block = js.match(/var legend = document\.getElementById\('nd2_netmap-legend'\);[\s\S]{0,900}?\n  \}/);
    assert.ok(block, 'netmap.js must carry the legend building block');
    assert.match(
      block[0],
      /\.title\s*=/,
      'clipping is only safe if the full string is still reachable. 28% of these labels ' +
      'are not uniquely identified by their visible first 42 characters, so without a ' +
      'title those rows are indistinguishable'
    );
    assert.match(
      block[0],
      /\.sort\(/,
      'Object.keys gives insertion order, which is the order nodes happened to arrive ' +
      'in the payload. The old renderer sorted its legend, and a 3152 row scroller in ' +
      'arrival order cannot be searched by eye'
    );
  });
});
