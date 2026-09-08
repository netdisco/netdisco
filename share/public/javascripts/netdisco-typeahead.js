// Suggestion menus for the fields that offer them. Fields declare themselves
// in markup, so nothing is initialized per pane and there is nothing to tear
// down when one is emptied. The logic is a set of pure functions, published on
// window.ndTypeahead, so it can be tested without a browser; everything that
// needs an element is below it.
(function () {
  'use strict';

  const ATTR = 'data-nd-typeahead';
  const MENU_ID = 'nd_typeahead-menu';
  const DELAY = 150;

  /**
   * Reads a field's typeahead configuration from its data attributes.
   * @param {Element} element the input carrying the attributes
   * @returns {{url: string, min: number, params: string[]|null, openTerm: string|null,
   *   opensOnFocus: boolean, first: boolean, menuClass: string, commit: string}} the settings
   */
  function readOptions(element) {
    const params = element.getAttribute(ATTR + '-params');
    return {
      url: element.getAttribute(ATTR) || '',
      min: Number(element.getAttribute(ATTR + '-min') || 0),
      params: params
        ? params
            .split(',')
            .map((s) => s.trim())
            .filter((s) => s.length)
        : null,
      openTerm: element.getAttribute(ATTR + '-open'),
      opensOnFocus: element.hasAttribute(ATTR + '-open'),
      first: element.hasAttribute(ATTR + '-first'),
      menuClass: element.getAttribute(ATTR + '-menu') || '',
      commit: element.getAttribute(ATTR + '-commit') || ''
    };
  }

  /**
   * Flattens either response shape the typeahead routes answer with into rows.
   * A flat list of strings shows what it stores; a list of objects shows one
   * string and stores another.
   * @param {unknown} payload the parsed JSON body
   * @returns {{label: string, value: string}[]} the rows, empty for anything unexpected
   */
  function normalizeRows(payload) {
    if (!Array.isArray(payload)) {
      return [];
    }
    return payload.map((row) => {
      if (row && typeof row === 'object') {
        return { label: String(row.label), value: String(row.value) };
      }
      return { label: String(row), value: String(row) };
    });
  }

  /**
   * Appends a row's label to a node, wrapping each occurrence of the typed term
   * in a strong element so the list shows why each row is in it. Built from text
   * nodes because the labels are device names out of the database, so nothing
   * here produces markup and nothing has to be escaped.
   * @param {Element} node the element the label is appended to
   * @param {string} label the row's label
   * @param {string} term the text typed so far, which may be empty
   * @returns {void}
   */
  function highlightInto(node, label, term) {
    const doc = node.ownerDocument;
    if (!term) {
      node.appendChild(doc.createTextNode(label));
      return;
    }
    const needle = term.toLowerCase();
    const hay = label.toLowerCase();
    let at = 0;
    let found = hay.indexOf(needle, at);
    while (found !== -1) {
      if (found > at) {
        node.appendChild(doc.createTextNode(label.slice(at, found)));
      }
      const strong = doc.createElement('strong');
      strong.appendChild(doc.createTextNode(label.slice(found, found + term.length)));
      node.appendChild(strong);
      at = found + term.length;
      found = hay.indexOf(needle, at);
    }
    if (at < label.length) {
      node.appendChild(doc.createTextNode(label.slice(at)));
    }
  }

  /**
   * Moves the active row. -1 is the typed text, which sits between the last row
   * and the first, so the list is a ring with the typed text as one of its
   * stops: walking off either end gives the typed text back rather than jumping
   * straight to the far row.
   * @param {number} current the active row, or -1 for the typed text
   * @param {number} count how many rows the menu holds
   * @param {number} direction 1 for down, -1 for up
   * @returns {number} the row to make active, or -1 for the typed text
   */
  function nextIndex(current, count, direction) {
    if (!count) {
      return -1;
    }
    const next = current + direction;
    if (next >= count) {
      return -1;
    }
    if (next < -1) {
      return count - 1;
    }
    return next;
  }

  /**
   * Dispatches the keydown the ACL editor's rule-add handler listens for.
   * @param {HTMLInputElement} field the field the row was written into
   * @returns {void}
   */
  function dispatchAclCommitKeydown(field) {
    field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
  }

  /**
   * @typedef {object} NdTypeaheadWindowProps
   * @property {object} [ndTypeahead] the readOptions, normalizeRows, highlightInto, nextIndex and dispatchAclCommitKeydown functions above, exported for tests
   */
  /** @type {Window & NdTypeaheadWindowProps} */
  const ndWindow = window;
  ndWindow.ndTypeahead = {
    readOptions: readOptions,
    normalizeRows: normalizeRows,
    highlightInto: highlightInto,
    nextIndex: nextIndex,
    dispatchAclCommitKeydown: dispatchAclCommitKeydown
  };

  /** @type {HTMLElement|null} the menu, built once and reused for the life of the page */
  let menu = null;
  /** @type {HTMLInputElement|null} the field the menu currently belongs to */
  let owner = null;
  /** @type {{label: string, value: string}[]} */
  let rows = [];
  /** @type {number} the active row, or -1 for the typed text */
  let active = -1;
  /** @type {string} what the person typed, which walking the rows must give back */
  let typed = '';
  /** @type {ReturnType<typeof readOptions>|null} */
  let options = null;
  let timer = null;
  /** @type {number} the newest request wins, whatever order the answers arrive in */
  let sequence = 0;
  /** @type {boolean} true while commit dispatches its own input event */
  let committing = false;

  /**
   * Suppresses the blur a press on the menu would otherwise cause. The menu is
   * torn down when focus leaves its field, so without this the click would
   * arrive after the row it was aimed at had gone.
   * @param {Event} event the mousedown on the menu
   * @returns {void}
   */
  function holdFocus(event) {
    event.preventDefault();
  }

  /**
   * Returns the menu, building it on first use.
   * @returns {HTMLElement} the one menu element
   */
  function theMenu() {
    if (menu) {
      return menu;
    }
    menu = document.createElement('ul');
    menu.className = 'nd_typeahead-menu';
    menu.setAttribute('role', 'listbox');
    menu.id = MENU_ID;
    menu.hidden = true;
    menu.addEventListener('mousedown', holdFocus);
    document.body.appendChild(menu);
    return menu;
  }

  /**
   * Hides the menu and gives up ownership of the field it belonged to.
   * @returns {void}
   */
  function close() {
    if (!owner) {
      return;
    }
    owner.setAttribute('aria-expanded', 'false');
    owner.removeAttribute('aria-activedescendant');
    theMenu().hidden = true;
    theMenu().className = 'nd_typeahead-menu';
    owner = null;
    rows = [];
    active = -1;
  }

  /**
   * Anchors the menu under its field in page coordinates, so it stays with the
   * field as the page scrolls. The navbar's own gap is a margin in the
   * stylesheet, which offsets an absolutely positioned box, so the other
   * sixteen menus hang flush as they always did.
   * @param {HTMLInputElement} field the field the menu hangs from
   * @returns {void}
   */
  function place(field) {
    const box = field.getBoundingClientRect();
    const list = theMenu();
    list.style.left = box.left + window.scrollX + 'px';
    list.style.top = box.bottom + window.scrollY + 'px';
    list.style.minWidth = box.width + 'px';
  }

  /**
   * Redraws the menu's rows and the field's ARIA state from the current rows.
   * @returns {void}
   */
  function paint() {
    const list = theMenu();
    while (list.firstChild) {
      list.removeChild(list.firstChild);
    }
    rows.forEach((row, index) => {
      const item = document.createElement('li');
      item.id = 'nd_typeahead-row-' + index;
      item.setAttribute('role', 'option');
      item.dataset.ndValue = row.value;
      const inner = document.createElement('div');
      highlightInto(inner, row.label, typed);
      item.appendChild(inner);
      if (index === active) {
        item.classList.add('nd_typeahead-active');
      }
      list.appendChild(item);
    });
    list.hidden = rows.length === 0;
    if (owner) {
      owner.setAttribute('aria-expanded', rows.length ? 'true' : 'false');
      if (active >= 0) {
        owner.setAttribute('aria-activedescendant', 'nd_typeahead-row-' + active);
      } else {
        owner.removeAttribute('aria-activedescendant');
      }
    }
  }

  /**
   * Builds the request a field's source expects. The serialized fields already
   * carry the typed text under their own names, which is why a request built
   * from them never adds a term of its own.
   * @param {HTMLInputElement} field the field being searched from
   * @param {string} term the text to send when the request carries a term
   * @param {ReturnType<typeof readOptions>} settings the field's own typeahead settings
   * @returns {{[key: string]: string}} the query parameters
   */
  function buildQuery(field, term, settings) {
    if (!settings.params) {
      return { term: term };
    }
    /** @type {{[key: string]: string}} */
    const query = {};
    settings.params.forEach((selector) => {
      const group =
        selector === 'self'
          ? [field]
          : /** @type {HTMLInputElement[]} */ (Array.from(document.querySelectorAll(selector)));
      group.forEach((input) => {
        if (input.name && !input.disabled) {
          query[input.name] = input.value;
        }
      });
    });
    return query;
  }

  /**
   * Fetches and shows the suggestions for a field.
   * @param {HTMLInputElement} field the field being searched from
   * @param {string} term the text to search for
   * @param {ReturnType<typeof readOptions>} settings the field's own typeahead settings
   * @returns {void}
   */
  function search(field, term, settings) {
    const mine = ++sequence;
    typed = field.value;
    $.get(
      uri_base + settings.url,
      buildQuery(field, term, settings),
      (data) => {
        if (mine !== sequence || owner !== field) {
          return;
        }
        rows = normalizeRows(data);
        active = settings.first && rows.length ? 0 : -1;
        place(field);
        paint();
      },
      'json'
    );
  }

  /**
   * Takes ownership of a field and schedules its search.
   * @param {HTMLInputElement} field the field the menu is opening for
   * @param {string} term the text to search for
   * @returns {void}
   */
  function open(field, term) {
    if (owner !== field) {
      close();
    }
    owner = field;
    const settings = readOptions(field);
    options = settings;
    theMenu().className = 'nd_typeahead-menu ' + settings.menuClass;
    field.setAttribute('role', 'combobox');
    field.setAttribute('aria-controls', MENU_ID);
    field.setAttribute('aria-autocomplete', 'list');
    if (timer) {
      clearTimeout(timer);
    }
    timer = setTimeout(() => search(field, term, settings), DELAY);
  }

  /**
   * Writes a chosen row into its field and closes the menu.
   * @param {HTMLInputElement} field the field being filled in
   * @param {{value: string}} row the chosen row
   * @param {boolean} fromEnter true when a live Enter keydown is choosing the row
   * @returns {void}
   */
  function commit(field, row, fromEnter) {
    const commitStyle = options ? options.commit : '';
    field.value = row.value;
    close();
    committing = true;
    // The widget this replaces did not do this, so the IP Inventory sidebar's
    // "never" option never saw a chosen prefix. The field colouring beside it
    // is driven by change, which the browser fires on blur either way.
    field.dispatchEvent(new Event('input', { bubbles: true }));
    committing = false;
    // Choosing a row with the pointer must still notify the contenteditable
    // keydown handler, because only a live Enter reaches it on its own.
    if (commitStyle === 'acl' && !fromEnter) {
      dispatchAclCommitKeydown(field);
    }
  }

  /**
   * Finds the typeahead field an event happened inside, if any.
   * @param {EventTarget|null} target the event's target
   * @returns {HTMLInputElement|null} the field, or null
   */
  function fieldFor(target) {
    const element = /** @type {Element|null} */ (target);
    return element && element.closest ? /** @type {HTMLInputElement|null} */ (element.closest('[' + ATTR + ']')) : null;
  }

  document.addEventListener('focusin', (event) => {
    const field = fieldFor(event.target);
    if (!field) {
      close();
      return;
    }
    const settings = readOptions(field);
    if (settings.opensOnFocus) {
      open(field, field.value || settings.openTerm || '');
    }
  });

  document.addEventListener('input', (event) => {
    const field = fieldFor(event.target);
    if (!field || committing) {
      return;
    }
    if (field.value.length < readOptions(field).min) {
      close();
      return;
    }
    open(field, field.value);
  });

  document.addEventListener('click', (event) => {
    const target = /** @type {Element} */ (event.target);
    const caret = target.closest && target.closest('.nd_topo_dev_caret, .nd_topo_port_caret');
    if (caret) {
      const sibling = /** @type {HTMLInputElement|null} */ (
        caret.parentNode && caret.parentNode.querySelector('[' + ATTR + ']')
      );
      if (!sibling) {
        return;
      }
      // The port caret asks for every port, so whatever is in the field has to
      // go before the request is built from it.
      if (caret.classList.contains('nd_topo_port_caret')) {
        sibling.value = '';
      }
      sibling.focus();
      open(sibling, sibling.value || readOptions(sibling).openTerm || '');
      return;
    }
    const row = /** @type {HTMLElement|null} */ (target.closest && target.closest('#' + MENU_ID + ' li'));
    if (row && owner) {
      commit(owner, { value: row.dataset.ndValue || '' }, false);
      return;
    }
    if (!fieldFor(target)) {
      close();
    }
  });

  document.addEventListener('keydown', (event) => {
    if (!owner || event.target !== owner || theMenu().hidden) {
      return;
    }
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      active = nextIndex(active, rows.length, event.key === 'ArrowDown' ? 1 : -1);
      owner.value = active === -1 ? typed : rows[active].value;
      paint();
    } else if (event.key === 'Escape') {
      event.preventDefault();
      owner.value = typed;
      close();
    } else if (event.key === 'Enter' && active !== -1) {
      event.preventDefault();
      commit(owner, rows[active], true);
    }
  });

  window.addEventListener('resize', () => {
    if (owner) {
      place(owner);
    }
  });

  // A field inside a scrolling sidebar walks away from a menu anchored in page
  // coordinates, so the menu goes rather than following it. The menu's own
  // scrollbar is the exception: it is taller than its 200px cap whenever the
  // answer runs long, and closing on that would make the rows below the fold
  // unreachable.
  document.addEventListener(
    'scroll',
    (event) => {
      if (owner && event.target !== document && event.target !== menu) {
        close();
      }
    },
    true
  );
})();
