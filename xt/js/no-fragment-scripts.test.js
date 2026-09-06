// The rule for netdisco's own JavaScript: it is static, so CodeQL reads it.
// Template Toolkit generates none of it, and no fragment carries a <script>
// other than a JSON data block, which is data rather than code.
//
// REMAINING is the allowlist of files still carrying template JavaScript. It
// exists so the rule can land before the conversion is finished and so each
// conversion is a one-line deletion here that a reviewer can see. It must be
// empty when the conversion is complete, and nothing may ever be added to it.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const VIEWS = path.join(ROOT, 'share', 'views');

// Files under share/views still carrying <script> with code, or a .js
// extension. Sorted. Delete a line when its file is converted.
const REMAINING = [
  'admintask.tt',
  'device.tt',
  'index.tt',
  'inventory.tt',
  'js/admintask.js',
  'js/common.js',
  'js/device.js',
  'js/report.js',
  'js/search.js',
  'layouts/main.tt',
  'report.tt',
  'search.tt',
  'sidebar/admintask/topology.tt',
  'sidebar/report/portlog.tt',
];

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else out.push(full);
  }
  return out;
}

const files = walk(VIEWS).map((f) => path.relative(VIEWS, f)).sort();

// A <script> that is code: any opening script tag whose type is not
// application/json and which has no src attribute.
const CODE_SCRIPT = /<script(?![^>]*\bsrc=)(?![^>]*type\s*=\s*["']application\/json["'])[^>]*>/i;

function carriesTemplateJavaScript(rel) {
  if (rel.endsWith('.js')) return true;
  const text = fs.readFileSync(path.join(VIEWS, rel), 'utf8');
  return CODE_SCRIPT.test(text);
}

test('views__every_file_carrying_javascript__is_on_the_remaining_list', () => {
  const offenders = files.filter(carriesTemplateJavaScript).filter((f) => !REMAINING.includes(f));
  assert.deepStrictEqual(offenders, [],
    'these files carry JavaScript the template generates; convert them rather than listing them');
});

test('remainingList__every_entry__still_exists_and_still_offends', () => {
  const stale = REMAINING.filter((f) => !files.includes(f) || !carriesTemplateJavaScript(f));
  assert.deepStrictEqual(stale, [],
    'converted or deleted, so delete its line here: the list must only shrink');
});

test('remainingList__is_sorted_with_no_duplicates', () => {
  const sorted = [...new Set(REMAINING)].sort();
  assert.deepStrictEqual(REMAINING, sorted);
});

// JSON blocks are the one script type allowed. htmx 2.0.10 executes only
// type '', text/javascript and module (isJavaScriptScriptNode), so a JSON
// block swapped in with a fragment is inert, and the browser never runs it.
test('fragments__every_json_script_block__has_an_id_and_parses', () => {
  const JSON_BLOCK = /<script[^>]*type\s*=\s*["']application\/json["'][^>]*>([\s\S]*?)<\/script>/gi;
  for (const rel of files.filter((f) => f.startsWith('ajax/'))) {
    const text = fs.readFileSync(path.join(VIEWS, rel), 'utf8');
    for (const m of text.matchAll(JSON_BLOCK)) {
      assert.match(m[0], /\bid\s*=/, rel + ': a JSON block needs an id for data-nd-data to name');
      // The body is a template directive at this point ([% results | none %])
      // or literal JSON; only literal JSON can be checked here.
      if (!m[1].includes('[%')) assert.doesNotThrow(() => JSON.parse(m[1]), rel + ': JSON block does not parse');
    }
  }
});

// A tab pane htmx has left is never emptied, so a stale sibling pane's own
// JSON block is still in the document when a freshly-swapped one is built;
// a block id shared by two fragments lets getElementById answer either
// build with the wrong pane's rows. Scanned across every view, not just
// ajax/, since a non-ajax template could carry one too.
test('fragments__json_script_block_ids__are_unique_across_all_views', () => {
  const ID_ATTR_BLOCK = /<script[^>]*type\s*=\s*["']application\/json["'][^>]*\bid\s*=\s*["']([^"']+)["'][^>]*>/gi;
  const filesById = {};
  for (const rel of files) {
    const text = fs.readFileSync(path.join(VIEWS, rel), 'utf8');
    for (const m of text.matchAll(ID_ATTR_BLOCK)) {
      (filesById[m[1]] = filesById[m[1]] || []).push(rel);
    }
  }
  const duplicates = Object.entries(filesById).filter(([, list]) => list.length > 1);
  assert.deepStrictEqual(duplicates, []);
});
