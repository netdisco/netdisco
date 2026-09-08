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
const REMAINING = [];

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

test('remainingList__after_the_conversion__is_empty', () => {
  assert.deepStrictEqual(REMAINING, [], 'the conversion is complete; nothing may be added back');
});

test('ourJavaScript__is_the_ten_static_files_and_two_sort_plugins', () => {
  const dir = path.join(ROOT, 'share', 'public', 'javascripts');
  const ours = fs.readdirSync(dir).filter((f) => /^(netdisco|portsort|versionsort)/.test(f)).sort();
  assert.deepStrictEqual(ours, [
    'netdisco-admin.js', 'netdisco-daterange.js', 'netdisco-deferred-nodes.js', 'netdisco-netmap.js',
    'netdisco-portcontrol.js', 'netdisco-request.js', 'netdisco-tables.js', 'netdisco-toast.js',
    'netdisco-typeahead.js', 'netdisco.js', 'portsort.js', 'versionsort.js',
  ]);
});

// Every check below is scoped to a <script> tag's own attribute string
// rather than the surrounding text, and the id lookup excludes a
// preceding hyphen, so an attribute name that merely contains another
// (data-id versus id) or a different attribute order (id before type)
// cannot be mistaken for the one being checked.
const SCRIPT_TAG = /<script([^>]*)>([\s\S]*?)<\/script\b[^>]*>/gi;
const JSON_TYPE = /type\s*=\s*["']application\/json["']/i;
const REAL_ID = /(?<!-)\bid\s*=\s*["']([^"']+)["']/i;

function jsonScriptBlocks(text) {
  const blocks = [];
  for (const m of text.matchAll(SCRIPT_TAG)) {
    const attrs = m[1];
    if (!JSON_TYPE.test(attrs)) continue;
    const idMatch = attrs.match(REAL_ID);
    blocks.push({ id: idMatch ? idMatch[1] : null, body: m[2] });
  }
  return blocks;
}

// JSON blocks are the one script type allowed. htmx 2.0.10 executes only
// type '', text/javascript and module (isJavaScriptScriptNode), so a JSON
// block swapped in with a fragment is inert, and the browser never runs it.
test('fragments__every_json_script_block__has_an_id_and_parses', () => {
  for (const rel of files.filter((f) => f.startsWith('ajax/'))) {
    const text = fs.readFileSync(path.join(VIEWS, rel), 'utf8');
    for (const block of jsonScriptBlocks(text)) {
      assert.ok(block.id, rel + ': a JSON block needs an id for data-nd-data to name');
      // The body is a template directive at this point ([% results | none %])
      // or literal JSON; only literal JSON can be checked here.
      if (!block.body.includes('[%')) assert.doesNotThrow(() => JSON.parse(block.body), rel + ': JSON block does not parse');
    }
  }
});

// A tab pane htmx has left is never emptied, so a stale sibling pane's own
// JSON block is still in the document when a freshly-swapped one is built;
// a block id shared by two fragments lets getElementById answer either
// build with the wrong pane's rows. Scanned across every view, not just
// ajax/, since a non-ajax template could carry one too.
test('fragments__json_script_block_ids__are_unique_across_all_views', () => {
  const filesById = {};
  for (const rel of files) {
    const text = fs.readFileSync(path.join(VIEWS, rel), 'utf8');
    for (const block of jsonScriptBlocks(text)) {
      if (!block.id) continue;
      (filesById[block.id] = filesById[block.id] || []).push(rel);
    }
  }
  const duplicates = Object.entries(filesById).filter(([, list]) => list.length > 1);
  assert.deepStrictEqual(duplicates, []);
});

// INCLUDE and PROCESS pull another template's markup into the block
// verbatim, which would let arbitrary HTML or a real <script> past a body
// that is supposed to be either literal JSON or one escaped expression.
test('jsonBlocks__every_body__has_no_include_or_process_directive', () => {
  const DIRECTIVE = /\[%[-+]?\s*(INCLUDE|PROCESS)\b/;
  for (const rel of files) {
    const text = fs.readFileSync(path.join(VIEWS, rel), 'utf8');
    for (const block of jsonScriptBlocks(text)) {
      assert.doesNotMatch(block.body, DIRECTIVE,
        rel + ': a JSON block must not INCLUDE or PROCESS another template');
    }
  }
});

// The JSON unicode escape for "<" keeps a value such as "</script>" from
// closing the block early when the browser parses the surrounding HTML;
// TT's own html_entity filter would escape to "&lt;", which JSON.parse
// does not understand, so the two must not be confused.
function expectedEscapedBody(name) {
  return "[% " + name + ".replace('<', '\\u003c') | none %]";
}

test('ajaxJsonBlocks__every_template_expression_body__uses_the_escaped_replace_form', () => {
  const NAME = /^\[%\s*(\w+)\.replace\(/;
  for (const rel of files.filter((f) => f.startsWith('ajax/'))) {
    const text = fs.readFileSync(path.join(VIEWS, rel), 'utf8');
    for (const block of jsonScriptBlocks(text)) {
      const body = block.body.trim();
      if (!body.includes('[%')) continue;
      const nameMatch = body.match(NAME);
      assert.ok(nameMatch, rel + ': template body is not the escaped replace expression: ' + body);
      assert.strictEqual(body, expectedEscapedBody(nameMatch[1]),
        rel + ': a JSON block interpolating a variable must escape "<" to the JSON unicode form');
    }
  }
});

// data-nd-data points a table at the JSON block carrying its rows; a typo
// or a renamed id would otherwise leave the table with no data and no
// visible error, since getElementById on a bad selector just returns null.
test('dataNdData__every_reference__names_an_id_present_in_the_same_file', () => {
  const REF = /data-nd-data\s*=\s*["']#([^"']+)["']/g;
  const ID_ATTR = new RegExp(REAL_ID.source, 'gi');
  for (const rel of files) {
    const text = fs.readFileSync(path.join(VIEWS, rel), 'utf8');
    const refs = [...text.matchAll(REF)].map((m) => m[1]);
    if (refs.length === 0) continue;
    const ids = new Set([...text.matchAll(ID_ATTR)].map((m) => m[1]));
    for (const ref of refs) {
      assert.ok(ids.has(ref), rel + ': data-nd-data references #' + ref + ', which has no id in this file');
    }
  }
});
