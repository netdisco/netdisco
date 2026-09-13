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

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');
const viewJsDir = path.join(repoRoot, 'share', 'views', 'js');
const codeqlConfigPath = path.join(repoRoot, '.github', 'codeql', 'codeql-config.yml');

// .github/ is not in MANIFEST, so the config is absent from a CPAN tarball.
// Skip rather than pass in that case: a passed assertion that never read the
// file would hide a real regression on a checkout where the file exists.
const skipWithoutConfig = !fs.existsSync(codeqlConfigPath)
  && 'no .github/codeql/codeql-config.yml (expected outside a git checkout)';

// The conversion this guard watched for is finished: every template under
// share/views/js/ went static, the directory is gone, and the exclusion it
// needed is gone with it. This is what stays behind to say so.
test('viewJsDirectory__after_the_conversion__no_longer_exists', () => {
  assert.ok(!fs.existsSync(viewJsDir), `${viewJsDir} still exists; it was to be removed once its templates went static`);
});

// Matched against paths-ignore entries only, not comment prose: another
// entry's comment can legitimately still say where its own fixtures come from.
test('codeqlConfig__after_the_conversion__no_longer_excludes_a_removed_directory', { skip: skipWithoutConfig }, () => {
  const config = fs.readFileSync(codeqlConfigPath, 'utf8');
  assert.doesNotMatch(config, /^\s*-\s*share\/views/m,
    'codeql-config.yml still excludes a share/views path, but the directory it excluded is gone');
});
