// Guards the two structural properties of the component that no behavior test
// can see: that it binds once on the document rather than per field, and that
// it never builds markup from a string.
//
// A source text test, deliberately. Both claims are about code that cannot run
// here: CI has no DOM. The behaviors themselves are covered by the harness.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const FILE = path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco-typeahead.js');
const source = fs.readFileSync(FILE, 'utf8');

// Per-element binding is what the widget this replaces did, and it is why a
// pane that was emptied natively leaked a menu and a live region per field.
test('typeahead__its_listeners__are_delegated_from_the_document', () => {
  assert.match(source, /document\.addEventListener\(\s*'focusin'/,
    'nothing listens for focusin on the document, so fields in a swapped pane get no menu');
  assert.match(source, /document\.addEventListener\(\s*'click'/,
    'nothing listens for click on the document, so the carets do nothing');
  assert.match(source, /document\.addEventListener\(\s*'keydown'/,
    'nothing listens for keydown on the document');
});

test('typeahead__the_component__never_assigns_innerHTML', () => {
  const offenders = source.split('\n')
    .map((line, i) => [i + 1, line])
    .filter(([, line]) => /\.innerHTML\s*=/.test(line) && !/^\s*\/\//.test(line));
  assert.deepEqual(offenders, [],
    'a label reaching the menu as markup is how a device name becomes script');
});

// The menu is one element for the life of the page. A component that made one
// per field would put the leak back.
test('typeahead__the_menu_element__is_created_once', () => {
  const creations = source.match(/createElement\(\s*'ul'\s*\)/g) || [];
  assert.equal(creations.length, 1,
    'more than one place builds a menu, so there is more than one menu');
});

// The one assertion that outlives this rung. Master carries a fix that reaches
// for jQuery UI by name, and it is merged into this branch later; if that merge
// keeps either side's call, the library is gone and the call is a TypeError
// nothing else here would report.
test('shippedScripts__after_the_library_is_gone__no_longer_call_it', () => {
  const dir = path.join(ROOT, 'share', 'public', 'javascripts');
  const ours = fs.readdirSync(dir).filter((name) => /^netdisco.*\.js$/.test(name));
  assert.ok(ours.length >= 6, 'the static scripts were not found');
  const offenders = [];
  ours.forEach((name) => {
    fs.readFileSync(path.join(dir, name), 'utf8').split('\n').forEach((line, i) => {
      if (/\.autocomplete\s*\(|ui-autocomplete|jquery-ui/.test(line)) {
        offenders.push(`${name}:${i + 1}`);
      }
    });
  });
  assert.deepEqual(offenders, [], 'these lines call a library the tree no longer ships');
});

test('typeahead__the_file__is_listed_in_the_layout_and_the_manifest', () => {
  const layout = fs.readFileSync(
    path.join(ROOT, 'share', 'views', 'layouts', 'main.tt'), 'utf8');
  assert.match(layout, /netdisco-typeahead\.js/, 'the layout does not load the component');
  const manifest = fs.readFileSync(path.join(ROOT, 'MANIFEST'), 'utf8');
  assert.match(manifest, /^share\/public\/javascripts\/netdisco-typeahead\.js$/m,
    'the component would be missing from the distribution tarball');
});
