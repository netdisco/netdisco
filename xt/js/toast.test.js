// Guards share/public/javascripts/netdisco-toast.js, the notifications drawn
// with Bootstrap's own toast component.
// CI runs node --test with no jsdom, so this builds only the handful of DOM
// pieces the module actually touches: elements with classes, attributes, a
// text node and two levels of descendant selector, nothing else.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ROOT = path.join(__dirname, '..', '..');
const source = fs.readFileSync(
  path.join(ROOT, 'share', 'public', 'javascripts', 'netdisco-toast.js'), 'utf8');

function allDescendants(root) {
  const found = [];
  const walk = (node) => {
    node.children.forEach((child) => {
      found.push(child);
      walk(child);
    });
  };
  walk(root);
  return found;
}

function matchesSimpleSelector(element, token) {
  return token.startsWith('.') ? element.classList.contains(token.slice(1)) : element.tagName === token.toUpperCase();
}

// One token per level of the selector, each level searched among the
// descendants of what the previous level matched. Enough for '.toast' and
// '.toast img', which is everything this module's markup needs.
function descendantsMatching(root, selector) {
  let contexts = [root];
  selector.trim().split(/\s+/).forEach((token) => {
    const next = [];
    contexts.forEach((context) => {
      allDescendants(context).forEach((candidate) => {
        if (matchesSimpleSelector(candidate, token)) next.push(candidate);
      });
    });
    contexts = next;
  });
  return contexts;
}

class FakeElement {
  constructor(tagName) {
    this.tagName = String(tagName).toUpperCase();
    this.children = [];
    this.parentNode = null;
    this.classSet = new Set();
    this.attrs = {};
    this.text = '';
    this.listeners = {};
  }

  get className() {
    return [...this.classSet].join(' ');
  }

  set className(value) {
    this.classSet = new Set(String(value).split(/\s+/).filter((name) => name.length));
  }

  get classList() {
    const self = this;
    return {
      add: (...names) => names.forEach((name) => self.classSet.add(name)),
      remove: (...names) => names.forEach((name) => self.classSet.delete(name)),
      contains: (name) => self.classSet.has(name),
    };
  }

  // Enough of closest() for the dismiss handler: one simple selector, walked
  // up through parentNode, which is all this module asks of it.
  closest(selector) {
    let node = this;
    while (node) {
      if (matchesSimpleSelector(node, selector)) return node;
      node = node.parentNode;
    }
    return null;
  }

  get textContent() {
    return this.children.length ? this.children.map((child) => child.textContent).join('') : this.text;
  }

  set textContent(value) {
    this.children = [];
    this.text = value;
  }

  // A real sink, not an inert property: any tag-shaped substring becomes an
  // actual child element, the same way a browser's innerHTML parses markup.
  // This is what makes the escaping tests below able to fail: assigning a
  // string with no "<...>" in it behaves exactly like textContent, but a
  // string carrying "<img ...>" materializes a real IMG element underneath,
  // which querySelectorAll('img') can then find.
  get innerHTML() {
    return this.children.length
      ? this.children.map((child) => '<' + child.tagName.toLowerCase() + '>').join('')
      : this.text;
  }

  set innerHTML(value) {
    this.children = [];
    this.text = '';
    const TAG = /<([a-zA-Z][a-zA-Z0-9-]*)\b[^>]*>/g;
    let match;
    let sawTag = false;
    while ((match = TAG.exec(String(value)))) {
      sawTag = true;
      this.appendChild(new FakeElement(match[1]));
    }
    if (!sawTag) {
      this.text = String(value);
    }
  }

  setAttribute(name, value) {
    this.attrs[name] = String(value);
  }

  getAttribute(name) {
    return Object.prototype.hasOwnProperty.call(this.attrs, name) ? this.attrs[name] : null;
  }

  appendChild(child) {
    child.parentNode = this;
    this.children.push(child);
    return child;
  }

  remove() {
    if (this.parentNode) {
      this.parentNode.children = this.parentNode.children.filter((sibling) => sibling !== this);
      this.parentNode = null;
    }
  }

  addEventListener(type, handler) {
    (this.listeners[type] = this.listeners[type] || []).push(handler);
  }

  dispatchEvent(type) {
    (this.listeners[type] || []).forEach((handler) => handler());
  }

  querySelectorAll(selector) {
    return descendantsMatching(this, selector);
  }

  querySelector(selector) {
    return descendantsMatching(this, selector)[0] || null;
  }
}

// A stand-in for bootstrap.Toast that only records the call; nothing here
// exercises the timed auto-hide, so show() need not simulate it.
class FakeBootstrapToast {
  constructor(element) {
    this.element = element;
    this.hidden = 0;
    element.bsToast = this;
  }

  show() {
    this.element.classList.add('show');
  }

  hide() {
    this.hidden += 1;
  }
}

// Fresh document and module for every test, so one test's toasts cannot be
// mistaken for another's when a test counts how many are showing.
function load() {
  const body = new FakeElement('body');
  const doc = {
    body,
    createElement: (tag) => new FakeElement(tag),
    querySelector: (selector) => body.querySelector(selector),
    querySelectorAll: (selector) => body.querySelectorAll(selector),
  };
  const win = { addEventListener() {}, document: doc };
  const sandbox = { window: win, document: doc, bootstrap: { Toast: FakeBootstrapToast } };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  // ndToast is a top-level const, like ndTables in netdisco-tables.js, so
  // other classic scripts can read it by name without a window property; a
  // second run in the same context is how a script outside the file reads it.
  const ndToast = vm.runInContext('ndToast', sandbox);
  assert.ok(ndToast, 'the file did not publish a global ndToast');
  return { ndToast, document: doc };
}

test('ndToast__an_error__is_rendered_with_the_error_styling', () => {
  const { ndToast, document } = load();
  ndToast.error('it broke', 'Discover');
  const toast = document.querySelector('.toast');
  assert.ok(toast.className.includes('nd_toast-error'));
  assert.ok(toast.textContent.includes('it broke'));
  assert.ok(toast.textContent.includes('Discover'));
});

test('ndToast__several_messages__stack_rather_than_replacing_each_other', () => {
  const { ndToast, document } = load();
  ndToast.info('one');
  ndToast.info('two');
  assert.equal(document.querySelectorAll('.toast').length, 2);
});

test('ndToast__a_message_holding_markup__is_escaped_not_rendered', () => {
  const { ndToast, document } = load();
  ndToast.success('<img src=x onerror=alert(1)>');
  assert.equal(document.querySelectorAll('.toast img').length, 0);
});

test('ndToast__the_hidden_event_fires__removes_the_toast_from_the_page', () => {
  const { ndToast, document } = load();
  ndToast.info('queued');
  const toast = document.querySelector('.toast');
  toast.dispatchEvent('hidden.bs.toast');
  assert.equal(document.querySelectorAll('.toast').length, 0);
});

test('ndToast__success_and_info__are_styled_for_their_own_kind', () => {
  const { ndToast, document } = load();
  ndToast.success('saved');
  ndToast.info('queued');
  const [first, second] = document.querySelectorAll('.toast');
  assert.ok(first.className.includes('nd_toast-success'));
  assert.ok(second.className.includes('nd_toast-info'));
});

// toastr dismissed on a tap anywhere, which is what the pointer cursor the
// stylesheet puts over a notification offers. The close button stays the
// library's own, so a click on it is not counted twice.
test('ndToast__clicked_anywhere_but_the_close_button__dismisses_itself', () => {
  const { ndToast, document } = load();
  ndToast.info('queued');
  const toast = document.querySelector('.toast');
  toast.listeners['click'][0]({ target: toast });
  assert.equal(toast.bsToast.hidden, 1, 'a tap on the body hides it');

  ndToast.info('again');
  const second = [...document.querySelectorAll('.toast')][1];
  const button = second.querySelector('.btn-close');
  second.listeners['click'][0]({ target: button });
  assert.equal(second.bsToast.hidden, 0, 'a tap on the close button is left alone');
});

test('ndToast__no_title_given__still_renders_the_message_alone', () => {
  const { ndToast, document } = load();
  ndToast.error('it broke');
  const toast = document.querySelector('.toast');
  assert.ok(toast.textContent.includes('it broke'));
});

// The interface being replaced always showed these at the top right, so the
// container is anchored there too rather than at whatever position a
// Bootstrap example happens to use.
test('ndToast__container_built_on_first_use__is_anchored_top_right', () => {
  const { ndToast, document } = load();
  ndToast.info('queued');
  const container = document.querySelector('.toast-container');
  assert.ok(container.className.includes('top-0'));
  assert.ok(!container.className.includes('bottom-0'));
  assert.ok(container.className.includes('end-0'));
});
