// The Swagger UI page's ?url= guard, executed rather than grepped. xt/32
// asserts the same logic as source text, which cannot tell a working guard from
// a broken one.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ROOT = path.join(__dirname, '..', '..');
const source = fs.readFileSync(
  path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco-swagger.js'), 'utf8');

// A stand-in window with no SwaggerUIBundle, so a file that starts the UI at
// load time fails here rather than in a browser.
function loadGuard(href) {
  const win = {
    location: { href, origin: new URL(href).origin, search: '' },
    addEventListener() {},
    document: { addEventListener() {}, getElementById: () => null },
  };
  const sandbox = { window: win, document: win.document, URL, URLSearchParams };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  assert.ok(win.ndSwagger, 'the file did not publish window.ndSwagger');
  assert.equal(typeof win.ndSwagger.sameOriginSpecUrl, 'function',
    'window.ndSwagger.sameOriginSpecUrl is not a function');
  return win.ndSwagger.sameOriginSpecUrl;
}

const AT = 'https://netdisco.example.net/swagger-ui/';

test('sameOriginSpecUrl__no_candidate__returns_null', () => {
  const guard = loadGuard(AT);
  assert.equal(guard(null), null);
  assert.equal(guard(''), null);
  assert.equal(guard(undefined), null);
});

test('sameOriginSpecUrl__same_origin_swagger_json__returns_the_path', () => {
  const guard = loadGuard(AT);
  assert.equal(guard('/swagger.json'), '/swagger.json');
});

test('sameOriginSpecUrl__a_relative_candidate__resolves_against_the_page', () => {
  const guard = loadGuard(AT);
  assert.equal(guard('../swagger.json'), '/swagger.json');
});

test('sameOriginSpecUrl__another_origin__returns_null', () => {
  const guard = loadGuard(AT);
  assert.equal(guard('https://evil.example.com/swagger.json'), null);
  assert.equal(guard('//evil.example.com/swagger.json'), null);
});

// The URL parser treats a backslash as a path separator for http and https, so
// this reads as relative to a string match and resolves off-origin.
test('sameOriginSpecUrl__a_backslash_authority__returns_null', () => {
  const guard = loadGuard(AT);
  assert.equal(guard('/\\evil.example.com/swagger.json'), null);
});

// Same origin alone would accept any JSON served from this host.
test('sameOriginSpecUrl__same_origin_but_another_path__returns_null', () => {
  const guard = loadGuard(AT);
  assert.equal(guard('/uploads/attacker.json'), null);
  assert.equal(guard('/swagger.json.txt'), null);
});

// A path-prefixed deployment still ends in /swagger.json.
test('sameOriginSpecUrl__a_path_prefixed_deployment__is_accepted', () => {
  const guard = loadGuard('https://netdisco.example.net/nd/swagger-ui/');
  assert.equal(guard('/nd/swagger.json'), '/nd/swagger.json');
});

test('sameOriginSpecUrl__a_query_string__is_carried_through', () => {
  const guard = loadGuard(AT);
  assert.equal(guard('/swagger.json?tenant=one'), '/swagger.json?tenant=one');
});

test('sameOriginSpecUrl__an_unparseable_candidate__returns_null', () => {
  const guard = loadGuard(AT);
  assert.equal(guard('http://['), null);
});


test('ndSwagger__the_module__exposes_the_default_spec_url', () => {
  const guard = loadGuard(AT);
  assert.ok(guard, 'guard loaded');
  const win = { location: { href: AT, origin: new URL(AT).origin, search: '' },
    addEventListener() {}, document: { addEventListener() {}, getElementById: () => null } };
  const sandbox = { window: win, document: win.document, URL, URLSearchParams };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  assert.equal(win.ndSwagger.DEFAULT_SPEC_URL, '../swagger.json');
});
