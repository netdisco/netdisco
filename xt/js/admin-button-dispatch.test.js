// Guards the delegated .nd_adminbutton click handler in netdisco-admin.js.
// The native DOM port (1b3174f6) returned early when the button had no
// enclosing <tr>, which silently broke the job queue's delete-all link: it
// lives in the tab bar, not in a table row, so the click was swallowed and
// /ajax/control/admin/jobqueue/delall was never posted. jQuery's
// $(this).closest('tr').find(...) had simply produced an empty field set.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const adminSource = fs.readFileSync(
  path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco-admin.js'), 'utf8');

class FakeElement {
  constructor(name, row) {
    this.name = name;
    this.row = row;
  }
  getAttribute(attr) { return attr === 'name' ? this.name : null; }
  closest(selector) {
    if (selector === '.nd_adminbutton') return this;
    if (selector === 'tr') return this.row;
    return null;
  }
}

// Runs ready() for the given tab and hands back the content pane's click
// listener plus the posts it made.
function readyAdminPage(tab) {
  const posts = [];
  let contentClick;
  const content = {
    addEventListener: (name, fn) => { if (name === 'click') contentClick = fn; },
    contains: () => true,
  };
  const documentMock = {
    body: { addEventListener: () => {} },
    addEventListener: () => {},
    getElementById: () => null,
    querySelector: (sel) => (sel === '.content' ? content : null),
  };
  const ndRequest = {
    post: (url, body) => {
      posts.push({ url, body });
      return new Promise(() => {});
    },
    fields: () => new URLSearchParams({ job: '42' }),
  };
  const ndPages = {};

  new Function(
    'document', 'window', 'ndPages', 'Element', 'ndRequest', 'ndToast', 'htmx',
    'bootstrap', 'uri_base', 'nd_active_tab', 'nd_active_target', 'activeForm',
    adminSource,
  )(
    documentMock, {}, ndPages, FakeElement, ndRequest, {}, { trigger: () => {} },
    { Popover: function () {} }, '', tab, '#' + tab + '_pane', null,
  );
  ndPages.admin.ready();

  const click = (button) => contentClick({ target: button, preventDefault: () => {} });
  return { click, posts };
}

test('adminButton__outside_any_row__still_posts_with_no_fields', () => {
  const { click, posts } = readyAdminPage('jobqueue');
  click(new FakeElement('delall', null));
  assert.strictEqual(posts.length, 1, 'the delete-all link must post');
  assert.strictEqual(posts[0].url, '/ajax/control/admin/jobqueue/delall');
  assert.strictEqual(posts[0].body.toString(), '');
});

test('adminButton__inside_a_row__posts_that_rows_fields', () => {
  const { click, posts } = readyAdminPage('jobqueue');
  click(new FakeElement('del', {}));
  assert.strictEqual(posts.length, 1);
  assert.strictEqual(posts[0].url, '/ajax/control/admin/jobqueue/del');
  assert.strictEqual(posts[0].body.toString(), 'job=42');
});
