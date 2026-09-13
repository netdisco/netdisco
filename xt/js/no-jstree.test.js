// jsTree was the last jQuery plugin the layout loaded on every page, so this is
// the assertion the jQuery removal depends on. It is a tree-wide scan rather
// than a check of one file, because the library was reachable from the layout,
// the pane script and the vendored directory.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');

test('shippedScripts__after_the_tree_is_server_rendered__do_not_mention_jstree', () => {
  const dir = path.join(ROOT, 'share', 'public', 'javascripts');
  const ours = fs.readdirSync(dir).filter((name) => /^netdisco.*\.js$/.test(name));
  assert.ok(ours.length >= 6, 'the static scripts were not found');
  const offenders = [];
  ours.forEach((name) => {
    fs.readFileSync(path.join(dir, name), 'utf8').split('\n').forEach((line, i) => {
      if (/jstree/i.test(line)) offenders.push(`${name}:${i + 1}`);
    });
  });
  assert.deepEqual(offenders, [], 'these lines drive a library the tree no longer ships');
});

test('theLibrary__and_its_theme__are_gone_from_the_distribution', () => {
  assert.ok(!fs.existsSync(path.join(ROOT, 'share', 'public', 'javascripts', 'jstree')),
    'the vendored directory is still present');
  const layout = fs.readFileSync(
    path.join(ROOT, 'share', 'views', 'layouts', 'main.tt'), 'utf8');
  assert.ok(!/jstree/i.test(layout), 'the layout still loads it');
  // the vendored path, not the bare name: this test's own entry carries it
  const manifest = fs.readFileSync(path.join(ROOT, 'MANIFEST'), 'utf8');
  assert.ok(!/javascripts\/jstree\//.test(manifest), 'the MANIFEST still lists it');
});

// It styles the device Modules tab, not this tree, and deleting it alongside
// the library would break a different page.
test('bootstrapTreeCss__which_belongs_to_the_modules_tab__is_kept', () => {
  assert.ok(fs.existsSync(path.join(ROOT, 'share', 'public', 'css', 'bootstrap-tree.css')),
    'the Modules tab lost its stylesheet');
  const modules = fs.readFileSync(
    path.join(ROOT, 'share', 'views', 'ajax', 'device', 'modules.tt'), 'utf8');
  assert.match(modules, /class="tree"/, 'the Modules tab no longer uses it');
});
