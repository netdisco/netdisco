// The toggle library ships two builds from one upstream release, both drawing
// the same widget from the same markup, so nothing else in the tree would
// notice the wrong one on disk.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const FILE = path.join(__dirname, '..', '..', 'share', 'public', 'javascripts',
  'bootstrap-toggle.min.js');

test('vendoredToggle__on_disk__is_the_plain_build', () => {
  const src = fs.readFileSync(FILE, 'utf8');
  assert.ok(!/jQuery/.test(src), 'the vendored file must not reference jQuery');
  assert.match(src, /bootstrap5-toggle/, 'this is not the toggle library at all');
  assert.match(src, /sourceMappingURL=bootstrap5-toggle\.ecmas\.min\.js\.map/,
    'the map reference must name the plain build');
});
