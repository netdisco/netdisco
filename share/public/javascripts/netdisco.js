// Must stay above every other statement here: this file executes during parse,
// so a request started from a DOMContentLoaded listener is already too late.
//
// htmx swaps a 4xx or 5xx body into the target by default. Left on, a Dancer
// error page replaces the pane's own failure message, and in a deferred
// connected-nodes box it destroys the indicator that box refuses to fetch
// without, so a box that failed once can never be clicked again.
htmx.config.noSwap = [204, 304, '4xx', '5xx'];

// Back and Forward re-request the page, which is what we want, but the library
// answers them by swapping the response into the body rather than navigating.
// That re-inserts the layout's script tags and runs them against a document
// that already ran them, so every const in them is declared twice and the page
// dies. Asking for a real reload is the same round trip without that.
htmx.config.history = 'reload';

// The library's own ceiling is 60 seconds, which a Ports tab on a large device
// has been measured to exceed. This one is far above any pane load ever
// observed, so it only ever cuts off a request that was never going to answer.
htmx.config.defaultTimeout = 300000;

// promoted from a <body> data attribute; the layout carries no inline
// JavaScript for CodeQL to skip.
var uri_base = document.body.dataset.ndUriBase;
var nd_check_userlog = (document.body.dataset.ndCheckUserlog === '1');

// a data-nd-has-sidebar="tab" marker of 0 means the tab ships no sidebar
// template. Shared with the htmx path, which does not call do_search.
function nd_has_sidebar(tab) {
  // A tab whose sidebar include throws renders the try block's marker (1)
  // and then the catch block's (0); a tab with its own sidebar template that
  // deliberately reports 0 renders that same 1 first, then its own 0. Either
  // way, the last marker in the document is the one taken as authoritative.
  var markers = document.querySelectorAll('[data-nd-has-sidebar="' + tab + '"]');
  var marker = markers[markers.length - 1];
  return marker ? marker.value !== '0' : true;
}

function nd_apply_sidebar (tab) {
  if (!nd_has_sidebar(tab)) {
    hideWithTooltip('.nd_sidebar, #nd_sidebar-toggle-img-out');
    document.querySelectorAll('.content').forEach(function (el) { el.style.marginRight = '10px' });
  }
  else {
    if (sidebar_hidden) {
      // netdisco.css sets #nd_sidebar-toggle-img-out { display: none }, so an
      // inline style of '' would not override it; the icon is an <i>, whose
      // own default display is inline.
      var toggleOut = document.getElementById('nd_sidebar-toggle-img-out');
      if (toggleOut) toggleOut.style.display = 'inline';
    }
    else {
      document.querySelectorAll('.content').forEach(function (el) { el.style.marginRight = '215px' });
      document.querySelectorAll('.nd_sidebar').forEach(function (el) { el.style.display = '' });
    }
  }
}

// Nothing shipped calls this. It is here for site-local code whose own
// submit handler still calls it; the shipped equivalent is the delegated
// submit listener in this file. It forwards with htmx.ajax() rather than by
// dispatching a submit event, which would re-enter the caller's own handler
// and recurse.
function do_search (event, tab) {
  event.preventDefault();
  nd_apply_sidebar(tab);

  console.error('do_search() now only forwards to htmx and will be removed in '
    + 'a future release. Give the #' + tab + '_form element the hx-get, '
    + 'hx-target, hx-headers and hx-indicator attributes used in '
    + 'share/views/device.tt, then drop this call. Run '
    + '"netdisco-do checksitelocal" to find every affected file.');

  // A site that overrode only this handler still has the shipped form, whose
  // hx-get has already loaded the pane off this same submit event.
  var form = document.getElementById(tab + '_form');
  if (form && form.getAttribute('hx-get')) { return }

  htmx.ajax('GET',
    uri_base + '/ajax/content/' + path + '/' + tab + '?'
      + (form ? ndRequest.query(form) : ''),
    { target: '#' + tab + '_pane',
      headers: { 'X-Requested-With': 'XMLHttpRequest' } });
}

/**
 * Registry of page scripts. A page's own file assigns an entry at load time,
 * before any ready callback runs, so this file can drive the page without
 * knowing which pages exist; the layout loads only the current page's script.
 * An entry is an object with up to three members:
 * formInputs() returns the array of inputs whose state colors the
 * sidebar form, or an empty array; innerView(tab) runs after every pane
 * swap on that page; ready() runs once when the page has loaded, reading the
 * active tab from nd_active_tab and nd_active_target.
 * @type {Object<string, {formInputs?: Function, innerView?: Function, ready?: Function}>}
 */
var ndPages = {};

// page, path, activeForm and form_inputs are set from the active page's
// ready block further down (device, search, report or admin), and read as
// globals here, in inner_view_processing, and by a registered page's own
// script. nd_active_tab and nd_active_target carry that ready block's local
// tab and target the same way, under names a registered page's ready() can
// read without shadowing the many local tab/target of the same name
// elsewhere in this file.
var page;
var path;
var activeForm;
var nd_active_tab;
var nd_active_target;
var form_inputs;
var sidebar_hidden = 0;

// on tab change, hide previous tab's search form and show new tab's
// search form. also trigger to load the content for the newly active tab.
function update_content(from, to) {
  var fromSearch = document.getElementById(from + '_search');
  if (fromSearch) fromSearch.classList.toggle('active');
  var toSearch = document.getElementById(to + '_search');
  if (toSearch) toSearch.classList.toggle('active');

  var to_form = '#' + to + '_form';

  // navbar text decoration special case
  if (to != 'device') {
    var nq = document.getElementById('nq');
    if (nq) nq.style.textDecoration = 'none';
  }
  else {
    form_inputs.forEach(function (input) { device_form_state(input) });
  }

  htmx.trigger(to_form, 'submit');
}

// if any field in Search Options has content, highlight in green
function device_form_state(field) {
  var with_val = form_inputs.filter(function (n) { return n.value != "" }).length;
  var with_text = form_inputs.filter(function (n) {
    return !n.matches('select') && n.value != "";
  }).length;

  // by id rather than a selector built from DOM text: the text can contain
  // characters a selector would read as syntax rather than literal content
  var clear_btn = document.getElementById(field.getAttribute('name') + '_clear_btn');

  if (field.value == "") {
    nd_clear_field_highlight(field, clear_btn, with_val, with_text);
  }
  else {
    nd_apply_field_highlight(field, clear_btn, with_val);
  }
}

/**
 * Unmarks a field that has just gone empty: drops its success styling, hides
 * its clear icon, and clears the navbar strikethrough and copy icons when
 * nothing else in the form still holds a value.
 * @param {Element} field the input or select that was cleared
 * @param {Element|null} clear_btn the field's own clear icon, if it has one
 * @param {number} with_val how many fields in the form still hold a value
 * @param {number} with_text how many text fields in the form still hold a value
 * @returns {void}
 */
function nd_clear_field_highlight(field, clear_btn, with_val, with_text) {
  var parent = field.parentElement;
  if (parent && parent.matches('.clearfix')) parent.classList.remove('success');
  hideWithTooltip(clear_btn);

  // if form has no field val, clear strikethough
  if (with_val == 0) {
    var nqReset = document.getElementById('nq');
    if (nqReset) nqReset.style.textDecoration = 'none';
  }

  // for text inputs only, extra formatting
  if (with_text == 0) {
    document.querySelectorAll('.nd_field-copy-icon').forEach(function (el) { el.style.display = '' });
  }
}

/**
 * Marks a field that now holds a value: adds its success styling, shows its
 * clear icon, sets the navbar strikethrough, and hides the copy icon for a
 * text field once it has something in it.
 * @param {Element} field the input or select that now holds a value
 * @param {Element|null} clear_btn the field's own clear icon, if it has one
 * @param {number} with_val how many fields in the form hold a value
 * @returns {void}
 */
function nd_apply_field_highlight(field, clear_btn, with_val) {
  var parent = field.parentElement;
  if (parent && parent.matches('.clearfix')) parent.classList.add('success');
  if (clear_btn) clear_btn.style.display = '';

  // if form still has any field val, set strikethough
  if (field.closest('form[action$="/search"]') && with_val != 0) {
    var nqStrike = document.getElementById('nq');
    if (nqStrike) nqStrike.style.textDecoration = 'line-through';
  }

  // if we're text, hide copy icon when we get a val
  if (field.getAttribute('type') == 'text') {
    document.querySelectorAll('.nd_field-copy-icon').forEach(function (el) { el.style.display = 'none' });
  }
}

// retitle a tooltip which is delegated from body. the delegate builds a
// per-element instance on first hover and caches it, so an existing
// instance must be disposed for the new title to be picked up.
function retitleTooltip(element, title) {
  if (!element) return;
  element.setAttribute('data-bs-title', title);
  var instance = bootstrap.Tooltip.getInstance(element);
  if (instance) { instance.dispose(); }
}

// Dismiss the tooltips of an element that is about to go away, and of any
// tooltip-carrying element inside it. Bootstrap dismisses a tip when the
// pointer leaves its trigger, but macOS Chrome fires no boundary event when the
// trigger is hidden or replaced under a pointer that has not moved, so nothing
// dismisses the tip and popper then anchors it to a zero sized rectangle at the
// window origin. Linux Chromium and Firefox both fire it, which is why #1667
// only ever reproduced on a Mac and why leaving this to the mouseleave handler
// below is not enough. The sidebar reset icon is the worst case: its tip is
// appended to body, so it outlives the anchor a pane response replaces.
function disposeTooltips(target) {
  var roots;
  if (typeof target === 'string') { roots = document.querySelectorAll(target); }
  else { roots = target ? [target] : []; }
  Array.prototype.forEach.call(roots, function (root) {
    var carriers = Array.prototype.slice.call(root.querySelectorAll('[rel=tooltip]'));
    if (root.matches('[rel=tooltip]')) carriers.push(root);
    carriers.forEach(function (el) {
      var instance = bootstrap.Tooltip.getInstance(el);
      if (instance) { instance.dispose(); }
    });
  });
}

// A delegated popover puts its instance on the row rather than on the element
// it was declared against, and appends the tip to body. A pane swap replaces
// the row and bootstrap dismisses nothing whose trigger has left the document,
// so the tips pile up one per refresh, keep the text of the job they described,
// and swallow the pointer for the row beneath them. The tip names its trigger
// through aria-describedby, which is the only way back to the instance; a tip
// whose trigger has already gone has none, and is just removed.
function disposePopovers() {
  document.querySelectorAll('.popover').forEach(function (el) {
    var trigger = el.id && document.querySelector('[aria-describedby="' + el.id + '"]');
    var instance = trigger && bootstrap.Popover.getInstance(trigger);
    if (instance) { instance.dispose(); }
    else { el.remove(); }
  });
}

function hideWithTooltip(target) {
  disposeTooltips(target);
  var elements;
  if (typeof target === 'string') { elements = document.querySelectorAll(target); }
  else { elements = target ? [target] : []; }
  Array.prototype.forEach.call(elements, function (el) { el.style.display = 'none' });
}

// Reveals an element a class or an earlier call hid. Clearing the inline
// style is not always enough: a class such as nd_collapse-pre-hidden also
// sets display:none, so a fallback is computed per element rather than
// assumed, by checking what actually became visible.
function nd_reveal(el) {
  el.style.display = '';
  if (window.getComputedStyle(el).display === 'none') { el.style.display = 'block'; }
}

function nd_toggle_display(el) {
  if (!el) return;
  if (window.getComputedStyle(el).display === 'none') { nd_reveal(el); }
  else { el.style.display = 'none'; }
}

// A pointer click focuses the category, which :focus-within then holds open
// after the pointer has left. detail is 0 for a keyboard-generated click, which
// must not close what it just opened.
document.addEventListener('click', function (event) {
  var category = event.target.closest('li.dropend > a.dropdown-toggle');
  if (category && event.detail > 0) { category.blur() }
});

/**
 * Queues one job for whatever the Discover box names, and says what happened.
 * The action's own admin route answers 400 for a device it will not take, so
 * an unresolvable name or too wide a prefix is reported rather than silently
 * dropped.
 * @param {string} action the job action to queue, such as discover or pingsweep
 * @param {string} [extra] the job's extra argument, the latency for a sweep
 * @returns {void}
 */
function nd_queue_disco_job(action, extra) {
  var box = /** @type {HTMLInputElement|null} */ (document.getElementById('discodevs'));
  if (!box || !box.value) { return }
  var target = box.value;
  var body = new URLSearchParams({ device: target });
  if (extra) { body.set('extra', extra) }

  ndRequest.post(uri_base + '/ajax/control/admin/' + action, body)
    .then(function (response) {
      if (response.ok) { ndToast.info('Queued ' + action + ' for ' + target) }
      else { ndToast.error('Could not queue ' + action + ' for ' + target) }
    }, function () {
      ndToast.error('Could not queue ' + action + ' for ' + target);
    });
}

/**
 * Which item an arrow key should focus within a dropend submenu, given how
 * many items it holds and which one has focus now. An index of -1 for the
 * current item means focus is on the submenu itself rather than an item.
 * @param {number} count how many items the submenu holds
 * @param {number} index the focused item's position, or -1 for none
 * @param {string} key the pressed key, 'ArrowUp' or 'ArrowDown'
 * @returns {number} the item to focus, or -1 to leave for the category above
 */
function nd_submenu_focus_index(count, index, key) {
  var wanted = (key === 'ArrowUp' ? index - 1 : index + 1);
  if (wanted < 0) { return -1 }
  // Bootstrap stops at the ends rather than cycling, so the top level and a
  // submenu feel the same.
  if (wanted >= count) { return index }
  return wanted;
}

// Bootstrap resolves the toggle to drive by looking beside the menu, and a
// dropend submenu's category link carries the dropdown-toggle class but not
// the data-bs-toggle attribute, so it finds nothing and throws on Escape and
// on either arrow. On window rather than document because Bootstrap registers
// its delegated handlers as capture listeners on document and loads first, so
// nothing there can precede them; stopping propagation is what keeps them from
// running, which is also why the arrows have to move focus here.
window.addEventListener('keydown', function (event) {
  var row = event.target.closest('li.dropend');
  if (!row) { return }
  var submenu = event.target.closest('li.dropend > .dropdown-menu');
  var category = row.querySelector(':scope > .dropdown-toggle');

  // Sideways is how a menu is meant to be walked: into a list that opens to the
  // side, and back out of it. The list stays on screen either way, because
  // focus is still inside the category that :focus-within holds open.
  if (event.key === 'ArrowRight' || event.key === 'ArrowLeft') {
    var into = (event.key === 'ArrowRight');
    if (into && event.target !== category) { return }
    if (!into && !submenu) { return }
    var landing = into
      ? row.querySelector(':scope > .dropdown-menu > li > .dropdown-item')
      : category;
    if (!landing) { return }
    event.preventDefault();
    event.stopPropagation();
    landing.focus();
    return;
  }

  // On a category, up and down step between the entries of the menu holding it.
  // Bootstrap walks every visible focusable descendant instead, and the list a
  // category holds open is one, so it descends into that list and the category
  // below is never reached. Sideways is how the list is entered.
  if (event.target === category
      && (event.key === 'ArrowUp' || event.key === 'ArrowDown')) {
    var peers = Array.prototype.slice.call(
      row.parentElement.querySelectorAll(':scope > li > .dropdown-item'));
    var peer = nd_submenu_focus_index(
      peers.length, peers.indexOf(category), event.key);
    event.preventDefault();
    event.stopPropagation();
    if (peer >= 0) { peers[peer].focus() }
    return;
  }

  if (!submenu) { return }

  if (event.key === 'Escape') {
    event.stopPropagation();
    var toggle = event.target.closest('.nav-item.dropdown');
    toggle = toggle && toggle.querySelector(':scope > .dropdown-toggle');
    if (!toggle) { return }
    toggle.focus();
    bootstrap.Dropdown.getOrCreateInstance(toggle).hide();
    return;
  }

  if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') { return }
  event.preventDefault();
  event.stopPropagation();

  var items = Array.prototype.slice.call(
    submenu.querySelectorAll(':scope > li > .dropdown-item'));
  var wanted = nd_submenu_focus_index(
    items.length, items.indexOf(event.target), event.key);

  // Leaving the submenu upward lands on the category that opened it, which is
  // in the menu Bootstrap can drive itself.
  var target = (wanted < 0
    ? submenu.parentElement.querySelector(':scope > .dropdown-toggle')
    : items[wanted]);
  if (target) { target.focus() }
}, true);

// htmx takes the indicator down when the response arrives, but the fragment's
// own script builds its table from a ready callback afterwards, so the raw
// full-length table would paint with no indicator until that finishes.
//
// Quiet DOM rather than a table library's own event. Quiet is not enough on
// its own: the build has gaps of several hundred milliseconds where nothing
// changes because the thread is busy computing, and revealing in one of
// those shows a table that is still moving.
// A frame that took far longer than a frame should is the evidence of that, so
// both conditions have to hold, twice running.
//
// The deadline is an escape hatch for a pane that never goes quiet rather than
// a budget: it starts at the swap, so it covers only the browser's own work,
// never the fetch.
function holdUntilSettled(pane, indicator) {
  if (!pane || !indicator) return;
  pane.classList.add('nd_pane-settling');
  indicator.classList.add('nd_indicator-held');

  var SMOOTH_FRAME = 50; // ms; a 60Hz frame is 16, and a busy one runs to 800
  var settledFrames = 0;
  var mutated = false;
  var previousFrame = null;
  var deadline = Date.now() + 60000;
  var watcher = new MutationObserver(function () { mutated = true });
  watcher.observe(pane, { childList: true, subtree: true, attributes: true });

  requestAnimationFrame(function frame(now) {
    var smooth = (previousFrame !== null) && ((now - previousFrame) < SMOOTH_FRAME);
    previousFrame = now;
    settledFrames = (smooth && !mutated) ? (settledFrames + 1) : 0;
    mutated = false;

    if (settledFrames < 2 && Date.now() < deadline) { requestAnimationFrame(frame); return }
    watcher.disconnect();
    pane.classList.remove('nd_pane-settling');
    indicator.classList.remove('nd_indicator-held');
  });
}

document.addEventListener('DOMContentLoaded', function() {
  // sidebar form fields should change colour and have bin/copy icon
  document.querySelectorAll('.nd_field-copy-icon').forEach(function (el) { el.style.display = 'none' });
  hideWithTooltip('.nd_field-clear-icon');

  // activate tooltips and popovers, delegated from a container so that
  // content injected later is covered without re-initialising. bootstrap
  // stores one instance per element whatever the component, so the popover
  // has to delegate from a different container than the tooltip.
  new bootstrap.Tooltip(document.body, { selector: '[rel=tooltip]' });
  new bootstrap.Popover(document.documentElement, { selector: '[rel=popover]' });

  // Dismiss a tooltip when the pointer leaves, even if the element still holds
  // focus. Both frameworks trigger on "hover focus", but the previous one hid
  // unconditionally on leave while the replacement keeps the tip up until blur,
  // stranding it over the content beside a sidebar field. Deliberately not
  // solved by dropping "focus" from the trigger, which would also stop a tooltip
  // appearing for someone tabbing through the form.
  document.body.addEventListener('mouseleave', function (event) {
    var eventTarget = event.target;
    var t = eventTarget instanceof Element ? eventTarget.closest('[rel=tooltip]') : null;
    // Native mouseenter/mouseleave fire separately at every ancestor whose own
    // boundary the pointer crossed, not just the delegate match, so a move
    // between an element's own children must not retrigger this.
    if (!t || !document.body.contains(t) || event.target !== t) return;
    var instance = bootstrap.Tooltip.getInstance(t);
    if (instance) { instance.hide(); }
  }, true);

  
// bind submission to the navbar go icon
  var navsearchgo = document.getElementById('navsearchgo');
  if (navsearchgo) {
    navsearchgo.addEventListener('click', function () {
      var form = navsearchgo.closest('form');
      if (form) form.submit();
    });
  }
  document.querySelectorAll('.nd_navsearchgo-specific').forEach(function (link) {
    link.addEventListener('click', function (event) {
      event.preventDefault();
      var form = link.closest('form');
      if (!form) return;

      var nqbody = document.getElementById('nqbody');
      if (nqbody && nqbody.value) {
        var tabField = document.createElement('input');
        tabField.type = 'hidden';
        tabField.name = 'tab';
        tabField.value = link.dataset.tab;
        form.appendChild(tabField);
        form.submit();
        return;
      }
      var nq = document.getElementById('nq');
      if (nq && nq.value) {
        var tabField2 = document.createElement('input');
        tabField2.type = 'hidden';
        tabField2.name = 'tab';
        tabField2.value = link.dataset.tab;
        form.appendChild(tabField2);
        form.submit();
        return;
      }
    });
  });

  // The Discover box queues its job over ajax rather than posting the form, so
  // the answer arrives where the reader is standing. Posting it navigated to
  // the job queue on success and silently back to this page on failure, which
  // is the same page a refused job returns to and says nothing about why.
  //
  // Its own listeners rather than the search dropdown's: that one finds the box
  // it fills by asking the document, so a value left in the navbar search took
  // precedence and submitted this form as a plain discover.
  var discoForm = document.querySelector('form[action$="/admin/discodevs"]');
  if (discoForm) {
    discoForm.addEventListener('submit', function (event) {
      event.preventDefault();
      nd_queue_disco_job('discover');
    });
    discoForm.addEventListener('click', function (event) {
      var sweep = event.target.closest('.dropdown-item[data-action]');
      if (!sweep) { return }
      event.preventDefault();
      nd_queue_disco_job(sweep.dataset.action, sweep.dataset.timeout);
    });
  }

  // fix green background on search checkboxes
  // https://github.com/twitter/bootstrap/issues/742
  var syncCheckBox = function() {
    var container = this.closest('.input-group-text');
    if (container) container.classList.toggle('active', this.checked);
  };
  document.querySelectorAll('.input-group-text input[type="checkbox"]').forEach(function (checkbox) {
    syncCheckBox.call(checkbox);
    checkbox.addEventListener('click', function () { syncCheckBox.call(checkbox) });
  });

  // sidebar toggle - pinning
  document.querySelectorAll('.nd_sidebar-pin').forEach(function (pinEl) {
    pinEl.addEventListener('click', function () {
      document.querySelectorAll('.nd_sidebar').forEach(function (el) { el.classList.toggle('nd_sidebar-pinned') });
      var pins = document.querySelectorAll('.nd_sidebar-pin');
      pins.forEach(function (el) { el.classList.toggle('nd_sidebar-pin-clicked') });
      // update tooltip note for current state
      var anyClicked = Array.prototype.some.call(pins, function (el) {
        return el.classList.contains('nd_sidebar-pin-clicked');
      });
      if (anyClicked) {
        retitleTooltip(pins[0], 'Unpin Sidebar');
      }
      else {
        retitleTooltip(pins[0], 'Pin Sidebar');
      }
    });
  });

  // sidebar toggle - trigger in/out on image click()
  //
  // This flips the sidebar instantly rather than sliding it over 250ms. No
  // interaction test exercises that transition (only its resting state, in
  // interact-sidebar.spec.js), so an instant flip is a deliberate choice
  // here, not an oversight.
  var sidebarToggleIn = document.getElementById('nd_sidebar-toggle-img-in');
  if (sidebarToggleIn) {
    sidebarToggleIn.addEventListener('click', function () {
      document.querySelectorAll('.nd_sidebar').forEach(function (el) { el.style.display = 'none' });
      // netdisco.css sets #nd_sidebar-toggle-img-out { display: none }; the
      // icon is an <i>, whose own default display is inline.
      var toggleOut = document.getElementById('nd_sidebar-toggle-img-out');
      if (toggleOut) toggleOut.style.display = 'inline';
      document.querySelectorAll('.content').forEach(function (el) { el.style.marginRight = '10px' });
      sidebar_hidden = 1;
    });
  }
  var sidebarToggleOut = document.getElementById('nd_sidebar-toggle-img-out');
  if (sidebarToggleOut) {
    sidebarToggleOut.addEventListener('click', function () {
      sidebarToggleOut.style.display = 'none';
      document.querySelectorAll('.content').forEach(function (el) { el.style.marginRight = '215px' });
      document.querySelectorAll('.nd_sidebar').forEach(function (el) { el.style.display = '' });
      var anyPinned = Array.prototype.some.call(document.querySelectorAll('.nd_sidebar'), function (el) {
        return el.classList.contains('nd_sidebar-pinned');
      });
      if (!anyPinned) {
        window.scrollTo(window.scrollX, 0);
      }
      sidebar_hidden = 0;
    });
  }

  // could not get twitter bootstrap tabs to behave, so implemented this
  // but warning! will probably not work for dropdowns in tabs
  document.querySelectorAll('#nd_search-results li').forEach(function (li) {
    li.addEventListener('click', function (event) {
      var eventTarget = event.target;
      var to_link = eventTarget instanceof Element ? eventTarget.closest('a') : null;
      if (!to_link || !li.contains(to_link)) return;
      event.preventDefault();
      // Bootstrap 5 reads "active" on the .nav-link, not on the <li>
      var from_link = document.querySelector('.nav-tabs > li > .nav-link.active');

      from_link.classList.toggle('active');
      to_link.classList.toggle('active');

      var from_id = from_link.getAttribute('href');
      var to_id = to_link.getAttribute('href');

      if (from_id == to_id) {
        return;
      }

      document.querySelector(from_id).classList.toggle('active');
      document.querySelector(to_id).classList.toggle('active');

      update_content(
        from_id.replace(/^#/,"").replace(/_pane$/,""),
        to_id.replace(/^#/,"").replace(/_pane$/,"")
      );
    });
  });

  // bootstrap modal mucks about with mouse actions on higher elements
  // so need to bury and raise it when needed
  document.querySelectorAll('.tab-pane').forEach(function (root) {
    root.addEventListener('show.bs.modal', function (event) {
      var eventTarget = event.target;
      var t = eventTarget instanceof Element ? eventTarget.closest('.nd_modal') : null;
      if (!t || !root.contains(t)) return;
      t.classList.toggle('nd_deep-horizon');
    });
    root.addEventListener('hidden.bs.modal', function (event) {
      var eventTarget = event.target;
      var t = eventTarget instanceof Element ? eventTarget.closest('.nd_modal') : null;
      if (!t || !root.contains(t)) return;
      t.classList.toggle('nd_deep-horizon');
    });
  });

  // inventory: a very large platform or OS table starts collapsed (see the
  // toggle() below); each Show link expands its own group's rows again.
  document.addEventListener('click', function (event) {
    var link = event.target.closest('.nd_collapse-inventory');
    if (!link) return;
    // data-target names a class shared by every row in the group, not a
    // single id, so all of them must toggle together.
    document.querySelectorAll(link.dataset.target).forEach(nd_toggle_display);
    var chevron = document.querySelector(link.dataset.chevron);
    if (chevron) { chevron.classList.toggle('fa-chevron-up'); chevron.classList.toggle('fa-chevron-down') }
  });

  // modules tab: collapsible nested <ul>, root scoped to the swapped pane so
  // a second modules fragment does not rebind the first one's tree.
  function nd_tree(root) {
    root.querySelectorAll('.tree > ul').forEach(function (ul) {
      ul.setAttribute('role', 'tree');
      ul.querySelectorAll('ul').forEach(function (nested) { nested.setAttribute('role', 'group') });
    });
    root.querySelectorAll('.tree li:has(ul)').forEach(function (li) {
      li.classList.add('parent_li');
      li.setAttribute('role', 'treeitem');
      var span = li.querySelector(':scope > span');
      if (!span) return;
      span.setAttribute('title', 'Collapse this branch');
      // This flips the branch instantly rather than sliding it, matching
      // the sidebar's own toggle above.
      span.addEventListener('click', function (e) {
        var children = li.querySelectorAll(':scope > ul > li');
        var icon = span.querySelector(':scope > i');
        var anyVisible = Array.prototype.some.call(children, function (child) {
          return window.getComputedStyle(child).display !== 'none';
        });
        if (anyVisible) {
          children.forEach(function (child) { child.style.display = 'none' });
          span.setAttribute('title', 'Expand this branch');
          if (icon) { icon.classList.add('fa-circle-plus'); icon.classList.remove('fa-circle-minus') }
        }
        else {
          children.forEach(function (child) { child.style.display = '' });
          span.setAttribute('title', 'Collapse this branch');
          if (icon) { icon.classList.add('fa-circle-minus'); icon.classList.remove('fa-circle-plus') }
        }
        e.stopPropagation();
      });
    });
  }

  // admintask orphaned devices: the chevron on an accordion header flips to
  // show which section is expanded. Bootstrap fires these as native events on
  // the collapsing element itself, so a body listener sees them regardless of
  // which accordion swapped in.
  document.body.addEventListener('show.bs.collapse', nd_accordion_chevron);
  document.body.addEventListener('hide.bs.collapse', nd_accordion_chevron);
  function nd_accordion_chevron(event) {
    var header = event.target.closest('.accordion') && event.target.previousElementSibling;
    var icon = header && header.classList.contains('accordion-header') && header.querySelector('a i');
    if (icon) { icon.classList.toggle('fa-chevron-up'); icon.classList.toggle('fa-chevron-down') }
  }

  // The newest pane request on the page, which is one request and not one per
  // pane: every sidebar form shares a queue on .nd_sidebar, so the request
  // htmx abandons when another tab is clicked belongs to the pane being left
  // and its replacement to the pane being opened. An abandoned request reports
  // its abort on the same event a real network failure uses, with nothing in
  // the event to tell them apart, and only the request the page is still
  // waiting on can be describing what the reader sees.
  var nd_latest_pane_request = null;

  // htmx glue. Converted panes get the same empty-result, error and
  // after-swap handling do_search gives the unconverted ones, so the two
  // transports are indistinguishable to a user. Keyed on any *_pane, not just
  // admin, because later rungs convert the search and device tabs onto this.
  document.body.addEventListener('htmx:after:swap', function (evt) {
    // One event per response, dispatched on the element that made the request,
    // so the pane is read from the context and never from the event.
    var ctx = evt.detail.ctx;
    var target = ctx.target;
    if (!target.id.match(/_pane$/)) return;
    // The status list stopped the swap, so the pane holds the failure message
    // the response-error handler put there and there is nothing to set up.
    if (ctx.response && ctx.response.status >= 400) return;
    var tab = target.id.replace(/_pane$/, '');
    if (target.innerHTML === '') {
      target.innerHTML =
        '<div class="col-md-2 alert alert-info">No matching records.</div>';
      return;
    }
    ndTables.init(target);
    if (target.querySelector('.tree')) nd_tree(target);
    holdUntilSettled(target, document.getElementById(tab + '_indicator'));
    inner_view_processing(tab);
  });
  // A search opens the tree to the node it found and marks it. That tree can
  // run to thousands of rows, so a mark below the fold says nothing on its own.
  document.body.addEventListener('htmx:after:swap', function (evt) {
    var target = evt.detail.ctx.target;
    if (!target || target.id !== 'nd_snmp-tree') { return }
    var hit = target.querySelector('.nd_snmp-found');
    if (hit) { hit.scrollIntoView({ block: 'center' }) }
  });

  // Empty the pane for the duration of the request, so the indicator is the
  // only thing on screen. Leaving the previous results up gives an interactive
  // table that no longer answers the search being run.
  //
  // jobqueue is excluded for the reason it carries no indicator: it refreshes
  // on a timer and would blank on every tick.
  document.body.addEventListener('htmx:before:request', function (evt) {
    var ctx = evt.detail.ctx;
    var target = ctx.target;
    if (!target.id.match(/_pane$/)) return;
    nd_latest_pane_request = ctx;

    disposePopovers();

    if (target.id === 'jobqueue_pane') return;

    // force-graph renders every frame until destroyed, and emptying the pane
    // only detaches its canvas. netdisco-netmap.js destroys the previous
    // instance too, but not until its own swap listener re-initializes.
    if (target.id === 'netmap_pane' && window.graph && window.graph.fg
        && typeof window.graph.fg._destructor === 'function') {
      window.graph.fg._destructor();
    }

    target.innerHTML = '';
  });
  document.body.addEventListener('htmx:response:error', function (evt) {
    var target = evt.detail.ctx.target;
    if (!target.id.match(/_pane$/)) return;
    // An expired session is not a fault the reader should report to anyone. The
    // server sends HX-Redirect with it, so this message is what remains on
    // screen for the moment before the browser leaves, and all that is left for
    // a request htmx did not make.
    var status = evt.detail.ctx.response && evt.detail.ctx.response.status;
    if (status === 401 || status === 403) return nd_session_expired(target);
    nd_pane_failure(target, 'server error');
  });
  // htmx puts a failed send, a timed out request, an abandoned request and an
  // exception thrown while displaying an answer on this one event. No context
  // at all means there was no request to fail, and an answer that arrived and
  // then failed is a display problem the reporter below owns. An abort is
  // neither, wherever in the exchange it landed: htmx sets the response before
  // it reads the body, so a request abandoned during the read arrives here
  // looking like it was answered.
  document.body.addEventListener('htmx:error', function (evt) {
    var ctx = evt.detail.ctx;
    if (!ctx) return;
    var error = evt.detail.error;
    var aborted = !!(error && error.name === 'AbortError');
    if (ctx.response && !aborted) return;
    var target = ctx.target;
    if (!target.id.match(/_pane$/)) return;
    if (nd_latest_pane_request !== ctx) return;
    // An abort nothing replaced is the ceiling in htmx.config.defaultTimeout
    // firing, which is worth naming: it sends an administrator looking at how
    // long the query takes rather than at the network.
    nd_pane_failure(target, aborted ? 'request timed out' : 'network error');
  });
  function nd_session_expired(pane) {
    // every part is a literal
    // eslint-disable-next-line no-unsanitized/property
    pane.innerHTML =
      '<div class="col-md-5 alert alert-warning"><i class="fas fa-right-to-bracket"></i> ' +
      'Your session has expired. <a href="' + nd_login_url() + '">Log in again</a> to carry on.</div>';
  }
  function nd_login_url() {
    return uri_base + '/login?return_url=' + encodeURIComponent(window.location.pathname + window.location.search);
  }
  function nd_pane_failure(pane, reason) {
    // every part is a literal, including reason: its three call sites pass one
    // of three fixed strings and nothing here comes from a response
    // eslint-disable-next-line no-unsanitized/property
    pane.innerHTML =
      '<div class="col-md-5 alert alert-danger"><i class="fas fa-triangle-exclamation"></i> ' +
      'Search failed! Please contact your site administrator (' + reason + ').</div>';
  }

  // A script error otherwise fails silently: htmx fires an event nobody
  // listens to, and an exception inside one of our own handlers reaches
  // nobody. One toast per page load; the console carries the detail.
  var ndReported = false;
  function nd_report_script_error(message, detail) {
    console.error(message, detail);
    if (ndReported) return;
    ndReported = true;
    ndToast.error('Something on this page failed. The browser console has the details.');
  }
  window.addEventListener('error', function (evt) {
    // a script from another origin reports only the bare "Script error."
    if (!evt.error && evt.message === 'Script error.') return;
    nd_report_script_error(evt.message, evt.error);
  });
  window.addEventListener('unhandledrejection', function (evt) {
    nd_report_script_error('Unhandled rejection', evt.reason);
  });
  // The pane handler above takes the failures whose answer never arrived, and
  // every abort, and says so in the pane itself. What is left to report as a
  // script error is a failure with no request behind it, or an answer that
  // arrived and could not be displayed.
  document.body.addEventListener('htmx:error', function (evt) {
    var error = evt.detail.error;
    if (error && error.name === 'AbortError') return;
    var ctx = evt.detail.ctx;
    if (ctx && !ctx.response) return;
    nd_report_script_error('Response could not be displayed', evt.detail);
  });

  // The chrome is replaced rather than hidden now, so the tip of an element
  // being swapped out has to go with it. htmx describes the whole response as
  // one list of swap tasks, which is also the only place a piece of chrome the
  // page has no element for is still visible: htmx builds no task for it and
  // drops it from the response without a word, which reads as the csv or reset
  // link quietly going stale. Most often a site-local page template that has
  // dropped one of the ids.
  document.body.addEventListener('htmx:before:swap', function (evt) {
    var ctx = evt.detail.ctx;
    // The chrome only. Walking the pane as well would scan every element of a
    // Ports table for a tip on the swap path, and the pane is already emptied
    // when its request starts.
    var chrome = evt.detail.tasks.filter(function (task) { return task.type === 'oob' });
    chrome.forEach(function (task) {
      if (task.target instanceof Element) { disposeTooltips(task.target) }
    });

    var offered = (ctx.text.match(/hx-swap-oob\s*=/g) || []).length;
    if (chrome.length < offered) {
      nd_report_script_error('This page has no element for '
        + (offered - chrome.length) + ' of the ' + offered
        + ' out-of-band items in the response', evt.detail);
    }

    // htmx takes a title from anywhere in the response and applies it even
    // where the status list has told it not to swap, so a server error page
    // would otherwise rename the browser tab.
    if (ctx.response && ctx.response.status >= 400) { ctx.title = '' }
  });
});


// index.tt: load System Information once its accordion is first opened,
// using {once: true} in place of a stats_loaded flag.
function nd_statistics_panel() {
  var stats = document.getElementById('nd_stats');
  var nqbody = document.getElementById('nqbody');
  if (nqbody) nqbody.focus(); // set focus to main search
  var loginuser = document.getElementById('loginuser');
  if (loginuser) loginuser.focus(); // set focus to login, if it's there

  var collapseStats = document.getElementById('collapse-stats');
  if (!collapseStats) return;

  collapseStats.addEventListener('show.bs.collapse', function() {
    fetch( stats.dataset.ndUrl,
      { headers: { 'X-Requested-With': 'XMLHttpRequest' } })
      .then( response => {
        if (! response.ok) {
          var status = document.getElementById('nd_stats_status');
          if (status) {
            status.classList.add('alert-danger');
            status.innerHTML = '<i class="fas fa-triangle-exclamation"></i> Failed to retrieve system information (server error).';
          }
          return;
          // throw new Error('Network response was not ok');
        }
        return response.text();
      })
      .then( content => {
        // A response.ok === false above resolves this with undefined; leave
        // the pane's error message in place rather than blanking it.
        if (content === undefined) return;
        var el = document.getElementById('nd_stats');
        // content is this page's own server-rendered fragment, from the same
        // route the fetch above just called
        // eslint-disable-next-line no-unsanitized/property
        if (el) el.innerHTML = content;
      })
      .catch( error => {
        var status = document.getElementById('nd_stats_status');
        if (status) {
          status.classList.add('alert-danger');
          // error is the fetch failure itself, never response content
          // eslint-disable-next-line no-unsanitized/property
          status.innerHTML = '<i class="fas fa-triangle-exclamation"></i> Failed to retrieve system information (network error: ' + error + ').';
        }
        console.error('There has been a problem with your fetch operation:', error);
      });
  }, { once: true });
}

// called after every ajax-loaded pane finishes settling, so a page's own
// script can react to the new content. do_search and the htmx glue above
// both call this unconditionally, so it must exist even on pages with
// nothing to do here.
function inner_view_processing(tab) {
  if (ndPages[page] && ndPages[page].innerView) {
    ndPages[page].innerView(tab);
  }
}

// each sidebar search form has a hidden copy of the main navbar search
function copy_navbar_to_sidebar (tab) {
  var form = document.getElementById(tab + '_form');

  // copy navbar value to currently active sidebar form
  var nq = document.getElementById('nq');
  if (nq && nq.value && form) {
    var activeQ = form.querySelector('input[name=q]');
    if (activeQ) activeQ.value = nq.value;
  }
  // then copy to all other inactive tab sidebars
  var currentValue = form ? (form.querySelector('input[name=q]') || {}).value : undefined;
  if (currentValue !== undefined) {
    document.querySelectorAll('form').forEach(function (otherForm) {
      otherForm.querySelectorAll('input[name=q]').forEach(function (input) {
        input.value = currentValue;
      });
    });
  }
}

/**
 * Binds the device page's sidebar controls: the port search options form,
 * its field-state highlighting, the filter box and its clear icon, the
 * collapser arrows, the port-name resubmit links, the VLANs column
 * collapser, and the netmap's show/pin/release/zoom/save controls.
 * @returns {void}
 */
function nd_setup_device_sidebar() {
    // fields in the Device Search Options form (Device tab)
    form_inputs = Array.prototype.slice.call(document.querySelectorAll(
      '#ports_form .clearfix input:not([type="checkbox"]), #ports_form .clearfix select'
    ));

    var portfilter = document.querySelector('#ports_form input[name=f]');

    // sidebar form fields should change colour and have trash/copy icon
    form_inputs.forEach(function (input) { device_form_state(input) });
    form_inputs.forEach(function (input) {
      input.addEventListener('change', function () { device_form_state(input) });
    });

    // sidebar collapser events trigger change of up/down arrow
    document.querySelectorAll('.collapse').forEach(function (el) {
      el.addEventListener('show.bs.collapse', function () {
        var container = el.parentElement;
        if (!container) return;
        Array.prototype.forEach.call(container.children, function (child) {
          if (child === el) return;
          child.querySelectorAll('.nd_arrow-up-down-right').forEach(function (arrow) {
            arrow.classList.toggle('fa-chevron-up'); arrow.classList.toggle('fa-chevron-down');
          });
        });
      });

      el.addEventListener('hide.bs.collapse', function () {
        var container = el.parentElement;
        if (!container) return;
        Array.prototype.forEach.call(container.children, function (child) {
          if (child === el) return;
          child.querySelectorAll('.nd_arrow-up-down-right').forEach(function (arrow) {
            arrow.classList.toggle('fa-chevron-up'); arrow.classList.toggle('fa-chevron-down');
          });
        });
      });
    });

    // if the user edits the filter box, revert to automagical search
    var portsForm = document.getElementById('ports_form');
    if (portsForm) {
      portsForm.addEventListener('input', function (event) {
        var eventTarget = event.target;
        var t = eventTarget instanceof Element ? eventTarget.closest('input[name=f]') : null;
        if (!t || !portsForm.contains(t)) return;
        var preferField = document.getElementById('nd_ports-form-prefer-field');
        if (preferField) preferField.setAttribute('value', '');
      });
    }

    // handler for trashcan icon in port filter box
    document.querySelectorAll('.nd_field-clear-icon').forEach(function (el) {
      el.addEventListener('click', function () {
        if (portfilter) portfilter.value = '';
        var preferField = document.getElementById('nd_ports-form-prefer-field');
        if (preferField) preferField.setAttribute('value', '');
        htmx.trigger('#ports_form', 'submit');
        device_form_state(portfilter); // will hide copy icons
      });
    });

    // allow port filter to have a preference for port/name/vlan
    if (portsForm) {
      portsForm.addEventListener('click', function (event) {
        var eventTarget = event.target;
        var t = eventTarget instanceof Element ? eventTarget.closest('.nd_device-port-submit-prefer') : null;
        if (!t || !portsForm.contains(t)) return;
        event.preventDefault();
        var preferField = document.getElementById('nd_ports-form-prefer-field');
        if (preferField) preferField.setAttribute('value', t.dataset.prefer);
        htmx.trigger('#ports_form', 'submit');
      });
    }

    // clickable device port names can simply resubmit AJAX rather than
    // fetch the whole page again.
    var portsPane = document.getElementById('ports_pane');
    if (portsPane) {
      portsPane.addEventListener('click', function (event) {
        var eventTarget = event.target;
        var t = eventTarget instanceof Element ? eventTarget.closest('.nd_this-port-only') : null;
        if (!t || !portsPane.contains(t)) return;
        event.preventDefault(); // link is real so prevent page submit

        var port = (t.textContent || '').trim();
        if (portfilter) portfilter.value = port;
        document.querySelectorAll('.nd_field-clear-icon').forEach(function (el) { el.style.display = '' });

        // make sure we're preferring a port filter
        var preferField = document.getElementById('nd_ports-form-prefer-field');
        if (preferField) preferField.setAttribute('value', 'port');

        htmx.trigger('#ports_form', 'submit');
        device_form_state(portfilter); // will hide copy icons
      });

      // VLANs column list collapser trigger
      // it's a bit of a faff because we can't easily use Bootstrap's collapser
      portsPane.addEventListener('click', function (event) {
        var eventTarget = event.target;
        var t = eventTarget instanceof Element ? eventTarget.closest('.nd_collapse-vlans') : null;
        if (!t || !portsPane.contains(t)) return;
        var nodesTotal = t.closest('.nd_nodes-total');
        var collapsing = nodesTotal && nodesTotal.nextElementSibling;
        if (collapsing && collapsing.matches('.nd_collapsing')) { nd_toggle_display(collapsing); }
        if (t.querySelector('.nd_arrow-up-down-left-down.fa-square-plus')) {
          t.innerHTML = 'Hide <div class="nd_arrow-up-down-left-up fas fa-square-minus"></div>&nbsp;';
        }
        else {
          t.innerHTML = 'Show <div class="nd_arrow-up-down-left-down fas fa-square-plus"></div>&nbsp;';
        }
      });
    }

    // netmap show controls. Setting any force-graph prop repaints, so
    // re-setting nodeRelSize to itself is the repaint call.
    var showIps = document.getElementById('nd_showips');
    if (showIps) {
      showIps.addEventListener('change', function () {
        window.graph.fg.nodeRelSize(window.graph.fg.nodeRelSize());
      });
    }
    var showSpeed = document.getElementById('nd_showspeed');
    if (showSpeed) {
      showSpeed.addEventListener('change', function () {
        window.graph.fg.nodeRelSize(window.graph.fg.nodeRelSize());
      });
    }

    // netmap pin/release controls
    var releaseAll = document.getElementById('nd_netmap-releaseall');
    if (releaseAll) {
      releaseAll.addEventListener('click', function (event) {
        event.preventDefault();
        window.graph.fg.graphData().nodes.forEach(function (n) { n.fx = undefined; n.fy = undefined });
        window.graph.fg.d3ReheatSimulation();
      });
    }
    var releaseOnly = document.getElementById('nd_netmap-releaseonly');
    if (releaseOnly) {
      releaseOnly.addEventListener('click', function (event) {
        event.preventDefault();
        window.graph.fg.graphData().nodes.forEach(function (n) {
          if (n.selected) { n.fx = undefined; n.fy = undefined }
        });
        window.graph.fg.d3ReheatSimulation();
      });
    }
    var pinOnly = document.getElementById('nd_netmap-pinonly');
    if (pinOnly) {
      pinOnly.addEventListener('click', function (event) {
        event.preventDefault();
        window.graph.fg.graphData().nodes.forEach(function (n) {
          if (n.selected) { n.fx = n.x; n.fy = n.y }
        });
      });
    }
    var zoomToDevice = document.getElementById('nd_netmap-zoomtodevice');
    if (zoomToDevice) {
      zoomToDevice.addEventListener('click', function (event) {
        event.preventDefault();
        var n = window.graph.nodeDataById(window.graph.centernode);
        window.graph.fg.centerAt(n.x, n.y, 600);
        window.graph.fg.zoom(4, 600);
      });
    }
    // true marks this as the user asking, which is what netdisco-netmap.js
    // keys the confirmation toast off
    var netmapSave = document.querySelector('#nd_netmap-save');
    if (netmapSave) netmapSave.addEventListener('click', function (event) {
      event.preventDefault();
      saveMapPositions(true);
    });
}

/**
 * Binds the report page's sidebar controls: the sidebar-hidden startup state,
 * the colored-input field highlighting, the trash icon in search forms, the
 * IP inventory subnet field's effect on the "never" checkbox, and the
 * add/update/delete forms embedded in the report table.
 * @param {string} tab the active report's tag, part of its route and form id
 * @param {string} target the CSS selector for the active report's tab pane
 * @returns {void}
 */
function nd_setup_report_sidebar(tab, target) {
    // some reports carry bind params but no configured sidebar, so they
    // start with the sidebar already hidden; mirrors the manual toggle below
    if (document.querySelector('form[data-nd-hide-sidebar]')) {
      document.querySelectorAll('.nd_sidebar').forEach(nd_toggle_display);
      // netdisco.css sets #nd_sidebar-toggle-img-out { display: none }; the
      // icon is an <i>, whose own default display is inline.
      var toggleOut = document.getElementById('nd_sidebar-toggle-img-out');
      if (toggleOut) toggleOut.style.display = 'inline';
      document.querySelectorAll('.content').forEach(function (el) { el.style.marginRight = '10px' });
      sidebar_hidden = 1;
    }

    // colored input fields in the Report Options sidebar forms
    form_inputs = Array.prototype.slice.call(document.querySelectorAll('.nd_colored-input'));

    // sidebar form fields should change colour and have trash icon
    form_inputs.forEach(function (input) { device_form_state(input) });
    form_inputs.forEach(function (input) {
      input.addEventListener('change', function () { device_form_state(input) });
    });

    // handler for bin icon in search forms
    document.querySelectorAll('.nd_field-clear-icon').forEach(function (el) {
      el.addEventListener('click', function () {
        var name = el.dataset.btnFor;
        var matches = document.querySelectorAll('[name=' + name + ']');
        matches.forEach(function (input) { input.value = ''; });
        if (matches[0]) device_form_state(matches[0]); // reset input field
      });
    });

    var ipinventorySubnet = document.getElementById('nd_ipinventory-subnet');
    if (ipinventorySubnet instanceof HTMLInputElement) {
      ipinventorySubnet.addEventListener('input', function () {
        var never = document.getElementById('never');
        if (!never) return;
        if (ipinventorySubnet.value.indexOf(':') != -1) {
          never.setAttribute('disabled', 'disabled');
        }
        else {
          never.removeAttribute('disabled');
        }
      });
    }

    // dynamically bind to all forms in the table
    var content = document.querySelector('.content');
    if (content) {
      content.addEventListener('click', function (event) {
        var eventTarget = event.target;
        var t = eventTarget instanceof Element ? eventTarget.closest('.nd_adminbutton') : null;
        if (!t || !content.contains(t)) return;
        // stop form from submitting normally
        event.preventDefault();

        // what purpose - add/update/del
        var mode = t.getAttribute('name');
        var row = t.closest('tr');
        if (!row) return;

        // collected before the pane is wiped below, which detaches this row
        var body = ndRequest.fields(row, 'input[data-form="' + mode + '"]');

        var targetEl = document.querySelector(target);
        if (targetEl) {
          targetEl.textContent = '';
          var alertDiv = document.createElement('div');
          alertDiv.className = 'col-md-2 alert';
          alertDiv.textContent = 'Request submitted...';
          targetEl.appendChild(alertDiv);
        }

        // submit the query and refresh the tab either way
        // TODO: fix sanity_ok in Netdisco Web, then report a request that
        // reached the server but failed separately from a network failure
        function refreshTab() { htmx.trigger('#' + tab + '_form', 'submit'); }
        ndRequest.post(uri_base + '/ajax/control/report/' + tab + '/' + mode, body)
          .then(refreshTab, refreshTab);
      });
    }
}

document.addEventListener('DOMContentLoaded', function() {
  if (document.getElementById('nd_stats')) { nd_statistics_panel(); }
  if (document.querySelector('.nd_inventory_collapser')) {
    document.querySelectorAll('.nd_inventory_collapser').forEach(nd_toggle_display);
  }

  page = document.body.dataset.ndPage;               // device, search, report, admin
  path = page;                                        // what do_search builds its fragment URL from
  activeForm = document.querySelector('.tab-pane.active form[data-nd-tab]');
  var tab = activeForm ? activeForm.dataset.ndTab : '';
  var target = '#' + tab + '_pane';
  nd_active_tab = tab;
  nd_active_target = target;

  if (page === 'device') {
    nd_setup_device_sidebar();

    // activity for admin tasks in device details
    var detailsPane = document.getElementById('details_pane');
    if (detailsPane) {
      detailsPane.addEventListener('click', function (event) {
        var eventTarget = event.target;
        var t = eventTarget instanceof Element ? eventTarget.closest('.nd_adminbutton') : null;
        if (!t || !detailsPane.contains(t)) return;
        // stop form from submitting normally
        event.preventDefault();

        // what purpose - discover/macsuck/arpnip
        var mode = t.getAttribute('name');
        var row = t.closest('tr');
        if (!row) return;

        // submit the query
        ndRequest.post(uri_base + '/ajax/control/admin/' + mode,
                       ndRequest.fields(row, 'input[data-form="' + mode + '"],textarea[data-form="' + mode + '"]'))
          .then(
            function (res) {
              // skip any error reporting for now
              // TODO: fix sanity_ok in Netdisco Web
              if (!res.ok) return ndToast.error('Failed to ' + mode + ' device ' + row.dataset.forDevice);
              if (mode != 'delete') {
                ndToast.info('Requested ' + mode + ' for device ' + row.dataset.forDevice);
                if (mode == 'snapshot_del') {
                  document.querySelectorAll('.nd_snap_btn').forEach(function (el) {
                    el.classList.toggle('btn-success');
                    el.classList.toggle('btn-info');
                  });
                  document.querySelectorAll('.nd_snap_func').forEach(function (el) { el.classList.toggle('disabled') });
                }
              }
              else {
                ndToast.success('Queued job to delete ' + row.dataset.forDevice);
              }
            },
            function () {
              ndToast.error('Failed to ' + mode + ' device ' + row.dataset.forDevice);
            }
          );
      });

      detailsPane.addEventListener('click', function (event) {
        var eventTarget = event.target;
        var t = eventTarget instanceof Element ? eventTarget.closest('.nd_nonadminbutton') : null;
        if (!t || !detailsPane.contains(t)) return;
        // stop form from submitting normally
        event.preventDefault();

        // what purpose - discover/macsuck/arpnip
        var mode = t.getAttribute('name');
        var row = t.closest('tr');
        if (!row) return;

        // submit the query
        ndRequest.post(uri_base + '/ajax/control/nonadmin/' + mode,
                       ndRequest.fields(row, 'input[data-form="' + mode + '"],textarea[data-form="' + mode + '"]'))
          .then(
            function (res) {
              // skip any error reporting for now
              // TODO: fix sanity_ok in Netdisco Web
              if (!res.ok) return ndToast.error('Failed to ' + mode + ' device ' + row.dataset.forDevice);
              ndToast.info('Requested ' + mode + ' for device ' + row.dataset.forDevice);
            },
            function () {
              ndToast.error('Failed to ' + mode + ' device ' + row.dataset.forDevice);
            }
          );
      });

      // clear any values in the delete confirm dialog
      detailsPane.addEventListener('hidden.bs.modal', function (event) {
        var eventTarget = event.target;
        var t = eventTarget instanceof Element ? eventTarget.closest('.nd_modal') : null;
        if (!t || !detailsPane.contains(t)) return;
        var log = document.getElementById('nd_devdel-log');
        if (log instanceof HTMLTextAreaElement) log.value = '';
        var archive = document.getElementById('nd_devdel-archive');
        if (archive instanceof HTMLInputElement) archive.removeAttribute('checked');
      });
    }
  }
  else if (page === 'search') {
    // fields in the Device Search Options form (Device tab)
    form_inputs = Array.prototype.slice.call(document.querySelectorAll(
      '#device_form .clearfix input:not([type="checkbox"]), #device_form .clearfix select'
    ));

    // sidebar form fields should change colour and have bin/copy icon
    form_inputs.forEach(function (input) { device_form_state(input) });
    form_inputs.forEach(function (input) {
      input.addEventListener('change', function () { device_form_state(input) });
    });

    // handler for copy icon in search option
    document.querySelectorAll('.nd_field-copy-icon').forEach(function (el) {
      el.addEventListener('click', function () {
        var name = el.dataset.btnFor;
        var input = document.querySelector('#device_form [name=' + name + ']');
        if (!input) return;
        var nq = document.getElementById('nq');
        if (nq) input.value = nq.value;
        device_form_state(input); // will hide copy icons
      });
    });

    // handler for bin icon in search option
    document.querySelectorAll('.nd_field-clear-icon').forEach(function (el) {
      el.addEventListener('click', function () {
        var name = el.dataset.btnFor;
        var input = document.querySelector('#device_form [name=' + name + ']');
        if (!input) return;
        input.value = '';
        device_form_state(input); // will hide copy icons
      });
    });
  }
  else if (page === 'report') {
    nd_setup_report_sidebar(tab, target);
  }
  else if (ndPages[page] && ndPages[page].ready) {
    form_inputs = ndPages[page].formInputs ? ndPages[page].formInputs() : [];
    ndPages[page].ready();
  }

  // Every sidebar form loads its own pane over htmx, declared by its hx-get.
  // This carries the side effects only and must not call preventDefault:
  // htmx's own submit listener does that.
  //
  // What this listener handles is what no response can answer: the navbar
  // copy writes into a form the response must never replace, and whether a
  // tab has a sidebar is declared by the sidebar templates rather than by
  // any route.
  document.addEventListener('submit', function (event) {
    var form = event.target;
    if (!form.matches('form[data-nd-tab]')) return;
    var submittedTab = form.dataset.ndTab;
    if (page === 'search' || page === 'device') copy_navbar_to_sidebar(submittedTab);
    nd_apply_sidebar(submittedTab);
  });

  // on page load, load the content for the active tab
  var active = document.body.dataset.ndActiveTab;
  if (active) {
    if (active === 'ipinventory' || active === 'subnets') {
      var submitEl = document.getElementById(active + '_submit');
      if (submitEl) submitEl.click();
    }
    else htmx.trigger('#' + active + '_form', 'submit');
  }

  // tenant change
  document.querySelectorAll('.nd_navtenant').forEach(function (link) {
    link.addEventListener('click', function (event) {
      event.preventDefault();
      var url = new URL(window.location.href);
      var newpath = url.pathname;
      newpath = newpath.replace(link.dataset.currenttenant, "");
      newpath = newpath.replace(document.body.dataset.ndPath, "/");
      newpath = newpath.replace("//", "/");
      newpath = link.dataset.tenantpath.concat(newpath, url.search);
      window.location = newpath;
    });
  });
});
