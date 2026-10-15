// Guards nd_statistics_panel in netdisco.js and the System Information panel in
// index.tt (#1735). The panel is rendered open, and Bootstrap fires no
// show.bs.collapse for a panel that starts open, so the content must be
// fetched at once rather than on first show, or the spinner never goes away.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const share = path.join(__dirname, '..', '..', 'share');
const source = fs.readFileSync(path.join(share, 'public', 'javascripts', 'netdisco.js'), 'utf8');
const template = fs.readFileSync(path.join(share, 'views', 'index.tt'), 'utf8');

// Take the shipped function text rather than a copy of it.
function extract(name) {
  const from = source.search(new RegExp('function\\s+' + name + '\\s*\\('));
  assert.notStrictEqual(from, -1, name + ' is not defined in netdisco.js');
  let depth = 0;
  for (let j = source.indexOf('{', from); j < source.length; j += 1) {
    if (source[j] === '{') depth += 1;
    if (source[j] === '}') { depth -= 1; if (depth === 0) return source.slice(from, j + 1); }
  }
  throw new Error('unbalanced braces in ' + name);
}

// Runs the panel setup against a page whose panel is open or closed, and
// returns the fetched URLs and a way to fire Bootstrap's show event.
function page({ open }) {
  const fetched = [];
  const listeners = [];
  const panel = {
    classList: { contains: (name) => open && name === 'show' },
    addEventListener: (type, handler, options) => listeners.push({ type, handler, options }),
  };
  const elements = {
    'nd_stats': { dataset: { ndUrl: '/ajax/content/statistics' } },
    'collapse-stats': panel,
  };
  const document = { getElementById: (id) => elements[id] || null };
  const fetch = (url) => { fetched.push(url); return new Promise(() => {}); };
  // eslint-disable-next-line no-new-func
  new Function('document', 'fetch', extract('nd_statistics_panel') + '; nd_statistics_panel();')(document, fetch);
  const show = () => listeners
    .filter((listener) => listener.type === 'show.bs.collapse')
    .forEach((listener) => listener.handler());
  return { fetched, listeners, show };
}

test('statisticsPanel__rendered_open__fetches_its_content_at_once', () => {
  assert.deepStrictEqual(page({ open: true }).fetched, ['/ajax/content/statistics']);
});

test('statisticsPanel__rendered_open_then_shown_again__fetches_only_once', () => {
  const panel = page({ open: true });
  panel.show();
  assert.deepStrictEqual(panel.fetched, ['/ajax/content/statistics']);
});

test('statisticsPanel__rendered_closed__fetches_on_first_show_only', () => {
  const panel = page({ open: false });
  assert.deepStrictEqual(panel.fetched, []);
  const showListeners = panel.listeners.filter((listener) => listener.type === 'show.bs.collapse');
  assert.strictEqual(showListeners.length, 1);
  assert.deepStrictEqual(showListeners[0].options, { once: true });
  panel.show();
  assert.deepStrictEqual(panel.fetched, ['/ajax/content/statistics']);
});

// The chevron flips on every show and hide, so its starting icon has to match
// the panel's starting state, or it points the wrong way from then on.
test('indexTemplate__system_information_panel__starts_open_with_a_down_chevron', () => {
  const block = template.slice(template.indexOf('id="accordion-statistics"'));
  assert.match(block, /id="collapse-stats" class="accordion-collapse collapse show"/);
  assert.match(block, /aria-expanded="true"/);
  assert.match(block, /<i class="fas fa-chevron-down nd_chevron"><\/i> System Information/);
});
