// The Native VLAN picker on the Ports tab. A port's VLAN is chosen from the
// device's own VLANs, which the page carries once in #nd-vlan-choices, so there
// is nothing to fetch and the list narrows as the person types. It borrows the
// typeahead's menu styling and its row helpers but not its widget: that one
// asks the server for each keystroke's rows and writes a row's value into its
// field, whereas this field shows a label and keeps the VLAN number it stands
// for in data-vlan. The logic is a set of pure functions, published on
// window.ndVlanPicker, so it can be tested without a browser; everything that
// needs an element is below them.
(function () {
  'use strict';

  const FIELD = '.nd_pvid-search';
  const CHOICES_ID = 'nd-vlan-choices';
  const MENU_ID = 'nd_vlan-menu';

  /**
   * Narrows the menu to the rows whose label holds what was typed, in any case.
   * @param {{label: string, value: string}[]} list every VLAN on offer
   * @param {string} term the text typed so far, which may be empty
   * @returns {{label: string, value: string}[]} the matching rows
   */
  function filterRows(list, term) {
    const needle = term.toLowerCase();
    return list.filter((row) => row.label.toLowerCase().includes(needle));
  }

  /**
   * Finds what a field shows for a VLAN number. A number the device has not
   * reported has no label, so it is shown as it stands.
   * @param {{label: string, value: string}[]} list every VLAN on offer
   * @param {string} vlan the VLAN number
   * @returns {string} the row's label, or the number itself
   */
  function labelFor(list, vlan) {
    const row = list.find((candidate) => candidate.value === vlan);
    return row ? row.label : vlan;
  }

  /**
   * Reads what was typed as a VLAN number, for when Enter is pressed with no
   * row chosen. The cell was a plain text field before it was a picker, and a
   * VLAN the device has not reported (so none of the rows) could be set from it.
   * @param {string} typed the text in the field
   * @returns {{label: string, value: string}|null} the row, or null when it is not a number
   */
  function typedRow(typed) {
    const number = typed.trim();
    return /^[1-9]\d*$/.test(number) ? { label: number, value: number } : null;
  }

  /**
   * @typedef {object} NdVlanPickerWindowProps
   * @property {object} [ndVlanPicker] the filterRows, labelFor and typedRow functions above, exported for tests
   */
  /** @type {Window & NdVlanPickerWindowProps} */
  const ndWindow = window;
  ndWindow.ndVlanPicker = {
    filterRows: filterRows,
    labelFor: labelFor,
    typedRow: typedRow
  };

  /** @type {HTMLElement|null} the menu, built once and reused for the life of the page */
  let menu = null;
  /** @type {HTMLInputElement|null} the field the menu currently belongs to */
  let owner = null;
  /** @type {{label: string, value: string}[]} every VLAN the device offers */
  let choices = [];
  /** @type {{label: string, value: string}[]} the rows the menu shows */
  let rows = [];
  /** @type {number} the active row, or -1 for none */
  let active = -1;

  /**
   * Returns the menu, building it on first use.
   * @returns {HTMLElement} the one menu element
   */
  function theMenu() {
    if (menu) {
      return menu;
    }
    menu = document.createElement('ul');
    menu.className = 'nd_typeahead-menu nd_vlan-menu';
    menu.setAttribute('role', 'listbox');
    menu.id = MENU_ID;
    menu.hidden = true;
    // Held here, not on the field: a press on a row would otherwise blur the
    // field, which closes the menu before the click can choose the row.
    menu.addEventListener('mousedown', (event) => event.preventDefault());
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
    owner = null;
    rows = [];
    active = -1;
  }

  /**
   * Anchors the menu to its field in page coordinates, above it when the field
   * is low in the window so that the rows are not left below the fold.
   * @param {HTMLInputElement} field the field the menu hangs from
   * @returns {void}
   */
  function place(field) {
    const box = field.getBoundingClientRect();
    const list = theMenu();
    list.style.left = box.left + window.scrollX + 'px';
    list.style.minWidth = box.width + 'px';
    const above = box.top > window.innerHeight * 0.66;
    list.style.top = (above ? box.top - list.offsetHeight : box.bottom) + window.scrollY + 'px';
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
      item.id = MENU_ID + '-row-' + index;
      item.setAttribute('role', 'option');
      const inner = document.createElement('div');
      ndTypeahead.highlightInto(inner, row.label, owner ? owner.value : '');
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
        owner.setAttribute('aria-activedescendant', MENU_ID + '-row-' + active);
        list.children[active].scrollIntoView({ block: 'nearest' });
      } else {
        owner.removeAttribute('aria-activedescendant');
      }
    }
  }

  /**
   * Shows the rows that match what is in the field. The menu is painted before
   * it is placed, because placing it above the field needs its height.
   * @param {HTMLInputElement} field the field the menu belongs to
   * @returns {void}
   */
  function narrow(field) {
    rows = filterRows(choices, field.value);
    active = -1;
    paint();
    place(field);
  }

  /**
   * Opens the menu on a field that has just taken focus. The field is emptied
   * so that typing narrows the list, and shows the VLAN it holds as its
   * placeholder meanwhile.
   * @param {HTMLInputElement} field the field that took focus
   * @returns {void}
   */
  function open(field) {
    const block = document.getElementById(CHOICES_ID);
    choices = block ? ndTypeahead.normalizeRows(JSON.parse(block.textContent || '[]')) : [];
    owner = field;
    field.placeholder = field.value;
    field.value = '';
    field.setAttribute('role', 'combobox');
    field.setAttribute('aria-controls', MENU_ID);
    field.setAttribute('aria-autocomplete', 'list');
    narrow(field);
  }

  /**
   * Puts the field back to showing the VLAN it holds, and closes the menu.
   * @param {HTMLInputElement} field the field that lost focus
   * @returns {void}
   */
  function settle(field) {
    field.value = labelFor(choices, field.dataset.vlan || '');
    field.placeholder = '';
    close();
  }

  /**
   * Makes a row the VLAN of the field and announces it, for the port control
   * code to confirm and save. Choosing the VLAN the field already holds
   * announces nothing.
   * @param {HTMLInputElement} field the field the row was chosen for
   * @param {{label: string, value: string}} row the chosen row
   * @returns {void}
   */
  function pick(field, row) {
    const changed = row.value !== field.dataset.vlan;
    field.dataset.vlan = row.value;
    // Blurring settles the field, which reads data-vlan back as the new label.
    field.blur();
    if (changed) {
      field.dispatchEvent(new CustomEvent('nd:vlan-picked', { bubbles: true }));
    }
  }

  /**
   * Finds the picker field an event happened inside, if any.
   * @param {EventTarget|null} target the event's target
   * @returns {HTMLInputElement|null} the field, or null
   */
  function fieldFor(target) {
    const element = /** @type {Element|null} */ (target);
    return element && element.closest ? /** @type {HTMLInputElement|null} */ (element.closest(FIELD)) : null;
  }

  document.addEventListener('focusin', (event) => {
    const field = fieldFor(event.target);
    if (field && field !== owner) {
      open(field);
    }
  });

  document.addEventListener('focusout', (event) => {
    const field = fieldFor(event.target);
    if (field) {
      settle(field);
    }
  });

  document.addEventListener('input', (event) => {
    const field = fieldFor(event.target);
    if (field && field === owner) {
      narrow(field);
    }
  });

  document.addEventListener('keydown', (event) => {
    if (!owner || event.target !== owner) {
      return;
    }
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      active = ndTypeahead.nextIndex(active, rows.length, event.key === 'ArrowDown' ? 1 : -1);
      paint();
    } else if (event.key === 'Escape') {
      event.preventDefault();
      owner.blur();
    } else if (event.key === 'Enter') {
      event.preventDefault();
      const row = active !== -1 ? rows[active] : typedRow(owner.value);
      if (row) {
        pick(owner, row);
      }
    }
  });

  document.addEventListener('click', (event) => {
    const target = /** @type {Element} */ (event.target);
    const item = target.closest && target.closest('#' + MENU_ID + ' li');
    if (item && owner) {
      pick(owner, rows[Array.from(theMenu().children).indexOf(item)]);
      return;
    }
    // The field is a small target in a much bigger cell, and a press anywhere
    // in the cell should open the picker.
    const cell = target.closest && target.closest('td[data-field="c_pvid"]');
    const field = cell && /** @type {HTMLInputElement|null} */ (cell.querySelector(FIELD));
    if (field && field !== document.activeElement) {
      field.focus();
    }
  });

  window.addEventListener('resize', () => {
    if (owner) {
      place(owner);
    }
  });
})();
