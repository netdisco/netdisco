// Keeps share/views/js/ honest about what CodeQL can read.
//
// Those files carry a .js extension but most are Template Toolkit sources.
// CodeQL's JavaScript extractor selects files by extension, so it opens each
// one, meets a [% where an expression belongs, and skips the file, reporting
// "Could not process some files due to syntax errors". A skipped file is not
// analyzed and nothing else says so: measured on 6d81a9d5, admintask.js was
// present in the CodeQL database with zero extracted expressions.
//
// The rule this enforces is that a file under that directory is either
// analyzable or deliberately excluded, never silently neither:
//
//   every .js file under share/views/js/
//     parses as JavaScript, OR is listed under paths-ignore in
//     .github/codeql/codeql-config.yml
//
// Both directions matter. A new template added there without an ignore entry
// drops out of analysis unnoticed, which is how this arose. An ignore entry for
// a file that has since been made to parse keeps hiding a file that no longer
// needs hiding.
//
// An interpolation inside a string literal parses, because to a JavaScript
// parser it is a string holding odd characters, so most of these files are fine
// as they stand. Only block control flow at statement position and an unquoted
// interpolation in expression position break it.

'use strict';

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const repoRoot = path.join(__dirname, '..', '..');
const viewJsDir = path.join(repoRoot, 'share', 'views', 'js');
const codeqlConfigPath = path.join(repoRoot, '.github', 'codeql', 'codeql-config.yml');

// .github/ is not in MANIFEST, so the config is absent from a CPAN tarball
// while share/views/js/ is present. Skip rather than pass in that case: an
// empty exception list would make the assertions below silently meaningless.
const configIsAbsent = !fs.existsSync(codeqlConfigPath);
const skipWithoutConfig =
  configIsAbsent && 'no .github/codeql/codeql-config.yml (expected outside a git checkout)';

function viewTemplates() {
  return fs.readdirSync(viewJsDir)
    .filter((name) => name.endsWith('.js'))
    .sort();
}

function parsesAsJavaScript(name) {
  try {
    // vm.Script compiles as a classic script, which is what these are. It
    // agrees with `node --check` on all six files as of 6d81a9d5.
    new vm.Script(fs.readFileSync(path.join(viewJsDir, name), 'utf8'));
    return true;
  }
  catch (error) {
    if (error instanceof SyntaxError) return false;
    throw error;
  }
}

// Line matching rather than a YAML parse, because the test must not give the
// repository a dependency for this. Returns null when the key is missing, which
// the first test below turns into a failure rather than an empty list.
function pathsIgnoreEntries() {
  const lines = fs.readFileSync(codeqlConfigPath, 'utf8').split('\n');
  const start = lines.findIndex((line) => /^paths-ignore:\s*$/.test(line));
  if (start === -1) return null;

  const entries = [];
  for (const line of lines.slice(start + 1)) {
    if (/^\S/.test(line)) break;
    const entry = /^\s+-\s+(\S+)\s*$/.exec(line);
    if (entry) entries.push(entry[1]);
  }
  return entries;
}

function excludedTemplates(entries) {
  const prefix = 'share/views/js/';
  return entries.filter((entry) => entry.startsWith(prefix)).map((entry) => entry.slice(prefix.length));
}

describe('the guard can see what it claims to guard', () => {
  // Runs everywhere, including from a tarball. Without it, moving or renaming
  // the directory would leave every assertion below iterating an empty list and
  // reporting success.
  test('viewJsDirectory__in_any_checkout__holds_the_files_the_guard_covers', () => {
    assert.ok(fs.existsSync(viewJsDir), `${viewJsDir} does not exist`);
    assert.ok(viewTemplates().length > 0, 'no .js files found under share/views/js/');
  });

  test('codeqlConfig__as_shipped__yields_a_non_empty_paths_ignore_list', { skip: skipWithoutConfig }, () => {
    const entries = pathsIgnoreEntries();
    assert.notEqual(entries, null,
      'no `paths-ignore:` key found in .github/codeql/codeql-config.yml. If the key was renamed or ' +
      'reindented, update pathsIgnoreEntries() in this file: an unparsed config yields an empty ' +
      'exception list, which would make the exclusion assertions below pass without checking anything.');
    assert.ok(entries.length > 0, 'the paths-ignore list parsed as empty');
  });
});

describe('agreement between the templates and the CodeQL config', () => {
  test('viewTemplates__with_a_js_extension__either_parse_or_are_excluded_from_scanning',
    { skip: skipWithoutConfig }, () => {
      const excluded = excludedTemplates(pathsIgnoreEntries() || []);
      const unanalyzed = viewTemplates()
        .filter((name) => !parsesAsJavaScript(name))
        .filter((name) => !excluded.includes(name));

      assert.deepStrictEqual(unanalyzed, [],
        `these files under share/views/js/ do not parse as JavaScript and are not excluded in ` +
        `.github/codeql/codeql-config.yml, so CodeQL skips them and analyzes nothing: ` +
        `${unanalyzed.join(', ')}. Either quote the interpolation that breaks the parse, or add the ` +
        `file to paths-ignore.`);
    });

  test('codeqlConfig__excluding_a_view_template__names_only_files_that_cannot_parse',
    { skip: skipWithoutConfig }, () => {
      const excluded = excludedTemplates(pathsIgnoreEntries() || []);
      const stale = excluded.filter((name) => fs.existsSync(path.join(viewJsDir, name)))
        .filter((name) => parsesAsJavaScript(name));

      assert.deepStrictEqual(stale, [],
        `these files are excluded in .github/codeql/codeql-config.yml but parse as JavaScript, so the ` +
        `exclusion is costing analysis for no reason: ${stale.join(', ')}. Remove them from paths-ignore.`);
    });
});
