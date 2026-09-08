// jQuery must not appear in a shipped script or the layout. This is a
// tree-wide scan rather than a check of one file, because every script on a
// page runs under the one layout, so any of them could reach it.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const JS = path.join(ROOT, 'share', 'public', 'javascripts');

test('shippedScripts__make_no_jQuery_calls', () => {
  const ours = fs.readdirSync(JS).filter((name) => /^netdisco.*\.js$/.test(name));
  assert.ok(ours.length >= 8, 'the static scripts were not found');
  const offenders = [];
  ours.forEach((name) => {
    fs.readFileSync(path.join(JS, name), 'utf8').split('\n').forEach((line, i) => {
      // A comment may legitimately name the library. Only a call is a defect.
      const code = line.replace(/^\s*(\/\/|\*).*$/, '');
      if (/\$\(|\bjQuery\b|\$\.\w/.test(code)) offenders.push(`${name}:${i + 1}`);
    });
  });
  assert.deepEqual(offenders, [], 'these lines call a library the tree does not ship');
});

test('theLibrary__is_gone_from_the_distribution', () => {
  assert.ok(!fs.existsSync(path.join(JS, 'jquery-latest.min.js')),
    'the vendored file is still present');
  const layout = fs.readFileSync(
    path.join(ROOT, 'share', 'views', 'layouts', 'main.tt'), 'utf8');
  assert.ok(!/jquery/i.test(layout), 'the layout still loads it');
  const manifest = fs.readFileSync(path.join(ROOT, 'MANIFEST'), 'utf8');
  assert.ok(!/jquery-latest/.test(manifest), 'the MANIFEST still lists it');
});
