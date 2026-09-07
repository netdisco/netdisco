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
  // way the last marker in the document is the one that used to win when
  // this was a plain object assignment.
  var markers = document.querySelectorAll('[data-nd-has-sidebar="' + tab + '"]');
  var marker = markers[markers.length - 1];
  return marker ? marker.value !== '0' : true;
}

function nd_apply_sidebar (tab) {
  if (!nd_has_sidebar(tab)) {
    hideWithTooltip('.nd_sidebar, #nd_sidebar-toggle-img-out');
    $('.content').css('margin-right', '10px');
  }
  else {
    if (sidebar_hidden) {
      $('#nd_sidebar-toggle-img-out').show();
    }
    else {
      $('.content').css('margin-right', '215px');
      $('.nd_sidebar').show();
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
    uri_base + '/ajax/content/' + path + '/' + tab + '?' + $('#' + tab + '_form').serialize(),
    { target: '#' + tab + '_pane',
      headers: { 'X-Requested-With': 'XMLHttpRequest' } });
}

/**
 * Registry of page scripts. A page's own file assigns an entry at load time,
 * before any ready callback runs, so this file can drive the page without
 * knowing which pages exist; the layout loads only the current page's script.
 * An entry is an object with up to three members:
 * formInputs() returns the jQuery collection of inputs whose state colors the
 * sidebar form, or an empty collection; innerView(tab) runs after every pane
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
  $('#' + from + '_search').toggleClass('active');
  $('#' + to + '_search').toggleClass('active');

  var to_form = '#' + to + '_form';

  // navbar text decoration special case
  if (to != 'device') {
    $('#nq').css('text-decoration', 'none');
  }
  else {
    form_inputs.each(function() {device_form_state($(this))});
  }

  htmx.trigger(to_form, 'submit');
}

// if any field in Search Options has content, highlight in green
function device_form_state(e) {
  var with_val = $.grep(form_inputs,
                        function(n,i) {return($(n).prop('value') != "")}).length;
  var with_text = $.grep(form_inputs.not('select'),
                          function(n,i) {return($(n).val() != "")}).length;

  // by id rather than a selector built from DOM text, which $() may read as
  // markup
  var clear_btn = document.getElementById(e.attr('name') + '_clear_btn');

  if (e.prop('value') == "") {
    e.parent(".clearfix").removeClass('success');
    hideWithTooltip(clear_btn);

    // if form has no field val, clear strikethough
    if (with_val == 0) {
      $('#nq').css('text-decoration', 'none');
    }

    // for text inputs only, extra formatting
    if (with_text == 0) {
      $('.nd_field-copy-icon').show();
    }
  }
  else {
    e.parent(".clearfix").addClass('success');
    $(clear_btn).show();

    // if form still has any field val, set strikethough
    if (e.parents('form[action$="/search"]').length > 0 && with_val != 0) {
      $('#nq').css('text-decoration', 'line-through');
    }

    // if we're text, hide copy icon when we get a val
    if (e.attr('type') == 'text') {
      $('.nd_field-copy-icon').hide();
    }
  }
}

// retitle a tooltip which is delegated from body. the delegate builds a
// per-element instance on first hover and caches it, so an existing
// instance must be disposed for the new title to be picked up.
function retitleTooltip(element, title) {
  $(element).attr('data-bs-title', title);
  var instance = bootstrap.Tooltip.getInstance($(element)[0]);
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
  $(target).find('[rel=tooltip]').addBack('[rel=tooltip]').each(function () {
    var instance = bootstrap.Tooltip.getInstance(this);
    if (instance) { instance.dispose(); }
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
  $('.popover').each(function () {
    var trigger = this.id && document.querySelector('[aria-describedby="' + this.id + '"]');
    var instance = trigger && bootstrap.Popover.getInstance(trigger);
    if (instance) { instance.dispose(); }
    else { this.remove(); }
  });
}

function hideWithTooltip(target) {
  disposeTooltips(target);
  $(target).hide();
}

// A pointer click focuses the category, which :focus-within then holds open
// after the pointer has left. detail is 0 for a keyboard-generated click, which
// must not close what it just opened.
document.addEventListener('click', function (event) {
  var category = event.target.closest('li.dropend > a.dropdown-toggle');
  if (category && event.detail > 0) { category.blur() }
});

// Bootstrap's own Escape handler builds a Dropdown from the nested list, finds
// no toggle beside it and throws, leaving the menu open. On window rather than
// document because Bootstrap registers its delegated handlers as capture
// listeners on document and loads first, so nothing there can precede them.
window.addEventListener('keydown', function (event) {
  if (event.key !== 'Escape') { return }
  if (!event.target.closest('li.dropend > .dropdown-menu')) { return }
  event.stopPropagation();
  var toggle = event.target.closest('.nav-item.dropdown');
  toggle = toggle && toggle.querySelector(':scope > .dropdown-toggle');
  if (!toggle) { return }
  toggle.focus();
  bootstrap.Dropdown.getOrCreateInstance(toggle).hide();
}, true);

// htmx takes the indicator down when the response arrives, but the fragment's
// own script builds its table from a ready callback afterwards, so the raw
// full-length table would paint with no indicator until that finishes.
//
// Quiet DOM rather than a table library's own event, so this outlives the move
// off jQuery. Quiet is not enough on its own: the build has gaps of several
// hundred milliseconds where nothing changes because the thread is busy
// computing, and revealing in one of those shows a table that is still moving.
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

$(document).ready(function() {
  // sidebar form fields should change colour and have bin/copy icon
  $('.nd_field-copy-icon').hide();
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
  $(document.body).on('mouseleave', '[rel=tooltip]', function() {
    var instance = bootstrap.Tooltip.getInstance(this);
    if (instance) { instance.hide(); }
  });

  // bind submission to the navbar go icon
  $('#navsearchgo').click(function() {
    $('#navsearchgo').parents('form').submit();
  });
  $('.nd_navsearchgo-specific').click(function(event) {
    event.preventDefault();
    if ($('#nqbody').val()) {
      $(this).parents('form').append(
        $(document.createElement('input')).attr('type', 'hidden')
                                          .attr('name', 'tab')
                                          .attr('value', $(this).data('tab'))
      ).submit();
      return;
    }
    if ($('#nq').val()) {
      $(this).parents('form').append(
        $(document.createElement('input')).attr('type', 'hidden')
                                          .attr('name', 'tab')
                                          .attr('value', $(this).data('tab'))
      ).submit();
      return;
    }
    if ($('#discodevs').val()) {
      $(this).parents('form').append(
        $(document.createElement('input')).attr('type', 'hidden')
                                          .attr('name', 'timeout')
                                          .attr('value', $(this).data('timeout'))
      ).append(
        $(document.createElement('input')).attr('type', 'hidden')
                                          .attr('name', 'action')
                                          .attr('value', $(this).data('action'))
      ).submit();
      return;
    }
  });

  // fix green background on search checkboxes
  // https://github.com/twitter/bootstrap/issues/742
  var syncCheckBox = function() {
    $(this).parents('.input-group-text').toggleClass('active', $(this).is(':checked'));
  };
  $('.input-group-text :checkbox').each(syncCheckBox).click(syncCheckBox);

  // sidebar toggle - pinning
  $('.nd_sidebar-pin').click(function() {
    $('.nd_sidebar').toggleClass('nd_sidebar-pinned');
    $('.nd_sidebar-pin').toggleClass('nd_sidebar-pin-clicked');
    // update tooltip note for current state
    if ($('.nd_sidebar-pin').hasClass('nd_sidebar-pin-clicked')) {
      retitleTooltip($('.nd_sidebar-pin').first(), 'Unpin Sidebar');
    }
    else {
      retitleTooltip($('.nd_sidebar-pin').first(), 'Pin Sidebar');
    }
  });

  // sidebar toggle - trigger in/out on image click()
  $('#nd_sidebar-toggle-img-in').click(function() {
    $('.nd_sidebar').toggle(250);
    $('#nd_sidebar-toggle-img-out').toggle();
    $('.content').css('margin-right', '10px');
    sidebar_hidden = 1;
  });
  $('#nd_sidebar-toggle-img-out').click(function() {
    $('#nd_sidebar-toggle-img-out').toggle();
    $('.content').css('margin-right', '215px');
    $('.nd_sidebar').toggle(250);
    if (! $('.nd_sidebar').hasClass('nd_sidebar-pinned')) {
        $(window).scrollTop(0);
    }
    sidebar_hidden = 0;
  });

  // could not get twitter bootstrap tabs to behave, so implemented this
  // but warning! will probably not work for dropdowns in tabs
  $('#nd_search-results li').delegate('a', 'click', function(event) {
    event.preventDefault();
    // Bootstrap 5 reads "active" on the .nav-link, not on the <li>
    var from_link = $('.nav-tabs').find('> li > .nav-link.active').first();
    var to_link = $(this);

    from_link.toggleClass('active');
    to_link.toggleClass('active');

    var from_id = from_link.attr('href');
    var to_id = to_link.attr('href');

    if (from_id == to_id) {
      return;
    }

    $(from_id).toggleClass('active');
    $(to_id).toggleClass('active');

    update_content(
      from_id.replace(/^#/,"").replace(/_pane$/,""),
      to_id.replace(/^#/,"").replace(/_pane$/,"")
    );
  });

  // bootstrap modal mucks about with mouse actions on higher elements
  // so need to bury and raise it when needed
  $('.tab-pane').on('show.bs.modal', '.nd_modal', function () {
    $(this).toggleClass('nd_deep-horizon');
  });
  $('.tab-pane').on('hidden.bs.modal', '.nd_modal', function () {
    $(this).toggleClass('nd_deep-horizon');
  });

  // activate daterange plugin
  $('#daterange').daterangepicker({
    ranges: {
      'Today': [moment(), moment()]
      ,'Yesterday': [moment().subtract(1, 'days'), moment().subtract(1, 'days')]
      ,'Last 7 Days': [moment().subtract(6, 'days'), moment()]
      ,'Last 30 Days': [moment().subtract(29, 'days'), moment()]
      ,'This Month': [moment().startOf('month'), moment().endOf('month')]
      ,'Last Month': [moment().subtract(1, 'month').startOf('month'), moment().subtract(1, 'month').endOf('month')]
    }
    // The plugin seeds its options from this element's data-* attributes and
    // lets the caller override them, so an unset option is the one a stray
    // attribute could supply. Both of these reach a jQuery HTML sink, so pin
    // them here rather than relying on the markup never gaining an attribute.
    //
    // The template is copied verbatim from daterangepicker 3.1.0, the version
    // named in package.json, where the plugin builds it at daterangepicker.js
    // lines 100 to 116. Re-copy it whenever that version changes: the plugin
    // queries selectors inside this container, so a stale copy renders a broken
    // widget with nothing thrown and no test to catch it.
    ,template:
      '<div class="daterangepicker">' +
        '<div class="ranges"></div>' +
        '<div class="drp-calendar left">' +
          '<div class="calendar-table"></div>' +
          '<div class="calendar-time"></div>' +
        '</div>' +
        '<div class="drp-calendar right">' +
          '<div class="calendar-table"></div>' +
          '<div class="calendar-time"></div>' +
        '</div>' +
        '<div class="drp-buttons">' +
          '<span class="drp-selected"></span>' +
          '<button class="cancelBtn" type="button"></button>' +
          '<button class="applyBtn" disabled="disabled" type="button"></button> ' +
        '</div>' +
      '</div>'
    ,parentEl: 'body'
    ,minDate: '2004-01-01'
    ,showDropdowns: true
    ,timePicker: false
    ,opens: 'left'
    ,locale: { format: 'YYYY-MM-DD', separator: ' to ' }
    ,autoUpdateInput: false
  }
  ,function(start, end) {
    $('#daterange').trigger('input');
  });

  // daterangepicker 3.x writes the picker's own dates into the input on init
  // unless autoUpdateInput is off, which blanks the server-rendered value. With
  // it off, nothing updates the input when a range is applied, so do it here.
  $('#daterange').on('apply.daterangepicker', function (ev, picker) {
    $(this).val(picker.startDate.format('YYYY-MM-DD')
      + ' to ' + picker.endDate.format('YYYY-MM-DD'));
    $(this).trigger('input');
  });

  // handler for datepicker in node sidebar
  $('.nd_sidebar').on('input', '#daterange', function() {
    if ($(this).prop('value') == '') {
      $('#daterange').parent('.clearfix').removeClass('success');
    }
    else {
      $('#daterange').parent('.clearfix').addClass('success');
    }
  });
  $('#daterange').trigger('input');

  // inventory: a very large platform or OS table starts collapsed (see the
  // toggle() below); each Show link expands its own group's rows again.
  document.addEventListener('click', function (event) {
    var link = event.target.closest('.nd_collapse-inventory');
    if (!link) return;
    $(link.dataset.target).toggle();
    $(link.dataset.chevron).toggleClass('fa-chevron-up fa-chevron-down');
  });

  // modules tab: collapsible nested <ul>, root scoped to the swapped pane so
  // a second modules fragment does not rebind the first one's tree.
  function nd_tree(root) {
    $(root).find('.tree > ul').attr('role', 'tree').find('ul').attr('role', 'group');
    $(root).find('.tree').find('li:has(ul)').addClass('parent_li').attr('role', 'treeitem').find(' > span').attr('title', 'Collapse this branch').on('click', function (e) {
      var children = $(this).parent('li.parent_li').find(' > ul > li');
      if (children.is(':visible')) {
        children.hide('fast');
        $(this).attr('title', 'Expand this branch').find(' > i').addClass('fa-circle-plus').removeClass('fa-circle-minus');
      }
      else {
        children.show('fast');
        $(this).attr('title', 'Collapse this branch').find(' > i').addClass('fa-circle-minus').removeClass('fa-circle-plus');
      }
      e.stopPropagation();
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
    toastr.error('Something on this page failed. The browser console has the details.');
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
  $('#nqbody').focus(); // set focus to main search
  $('#loginuser').focus(); // set focus to login, if it's there

  var collapseStats = document.getElementById('collapse-stats');
  if (!collapseStats) return;

  collapseStats.addEventListener('show.bs.collapse', function() {
    fetch( stats.dataset.ndUrl,
      { headers: { 'X-Requested-With': 'XMLHttpRequest' } })
      .then( response => {
        if (! response.ok) {
          $('#nd_stats_status').addClass('alert-danger')
            .html('<i class="fas fa-triangle-exclamation"></i> Failed to retrieve system information (server error).');
          return;
          // throw new Error('Network response was not ok');
        }
        return response.text();
      })
      .then( content => {
        $('#nd_stats').html(content);
      })
      .catch( error => {
        $('#nd_stats_status').addClass('alert-danger')
          .html('<i class="fas fa-triangle-exclamation"></i> Failed to retrieve system information (network error: ' + error + ').');
        console.error('There has been a problem with your fetch operation:', error);
      });
  }, { once: true });
}

// called after every ajax-loaded pane finishes settling, for per-page glue
// that jQuery delegation cannot express. do_search and the htmx glue above
// both call this unconditionally, so it must exist even on pages with
// nothing to do here.
function inner_view_processing(tab) {
  if (ndPages[page] && ndPages[page].innerView) {
    ndPages[page].innerView(tab);
  }
}

// each sidebar search form has a hidden copy of the main navbar search
function copy_navbar_to_sidebar (tab) {
  var form = '#' + tab + '_form';

  // copy navbar value to currently active sidebar form
  if ($('#nq').val()) {
    $(form).find("input[name=q]").val( $('#nq').val() );
  }
  // then copy to all other inactive tab sidebars
  $('form').find("input[name=q]").each( function() {
    $(this).val( $(form).find("input[name=q]").val() );
  });
}

$(document).ready(function() {
  if (document.getElementById('nd_stats')) { nd_statistics_panel(); }
  if (document.querySelector('.nd_inventory_collapser')) { $('.nd_inventory_collapser').toggle(); }

  page = document.body.dataset.ndPage;               // device, search, report, admin
  path = page;                                        // what do_search builds its fragment URL from
  activeForm = document.querySelector('.tab-pane.active form[data-nd-tab]');
  var tab = activeForm ? activeForm.dataset.ndTab : '';
  var target = '#' + tab + '_pane';
  nd_active_tab = tab;
  nd_active_target = target;

  if (page === 'device') {
    // fields in the Device Search Options form (Device tab)
    form_inputs = $("#ports_form .clearfix input").not('[type="checkbox"]')
        .add("#ports_form .clearfix select");

    var portfilter = $('#ports_form').find("input[name=f]");

    // sidebar form fields should change colour and have trash/copy icon
    form_inputs.each(function() {device_form_state($(this))});
    form_inputs.change(function() {device_form_state($(this))});

    // sidebar collapser events trigger change of up/down arrow
    $('.collapse').on('show.bs.collapse', function() {
      $(this).siblings().find('.nd_arrow-up-down-right')
        .toggleClass('fa-chevron-up fa-chevron-down');
    });

    $('.collapse').on('hide.bs.collapse', function() {
      $(this).siblings().find('.nd_arrow-up-down-right')
        .toggleClass('fa-chevron-up fa-chevron-down');
    });

    // if the user edits the filter box, revert to automagical search
    $('#ports_form').on('input', "input[name=f]", function() {
      $('#nd_ports-form-prefer-field').attr('value', '');
    });

    // handler for trashcan icon in port filter box
    $('.nd_field-clear-icon').click(function() {
      portfilter.val('');
      $('#nd_ports-form-prefer-field').attr('value', '');
      htmx.trigger('#ports_form', 'submit');
      device_form_state(portfilter); // will hide copy icons
    });

    // allow port filter to have a preference for port/name/vlan
    $('#ports_form').on('click', '.nd_device-port-submit-prefer', function() {
      event.preventDefault();
      $('#nd_ports-form-prefer-field').attr('value', $(this).data('prefer'));
      htmx.trigger('#ports_form', 'submit');
    });

    // clickable device port names can simply resubmit AJAX rather than
    // fetch the whole page again.
    $('#ports_pane').on('click', '.nd_this-port-only', function(event) {
      event.preventDefault(); // link is real so prevent page submit

      var port = $(this).text();
      port = $.trim(port);
      portfilter.val(port);
      $('.nd_field-clear-icon').show();

      // make sure we're preferring a port filter
      $('#nd_ports-form-prefer-field').attr('value', 'port');

      htmx.trigger('#ports_form', 'submit');
      device_form_state(portfilter); // will hide copy icons
    });

    // VLANs column list collapser trigger
    // it's a bit of a faff because we can't easily use Bootstrap's collapser
    $('#ports_pane').on('click', '.nd_collapse-vlans', function() {
        $(this).closest('.nd_nodes-total').next('.nd_collapsing').toggle();
        if ($(this).find('.nd_arrow-up-down-left-down').hasClass('fa-square-plus')) {
          $(this).html('Hide <div class="nd_arrow-up-down-left-up fas fa-square-minus"></div>&nbsp;');
        }
        else {
          $(this).html('Show <div class="nd_arrow-up-down-left-down fas fa-square-plus"></div>&nbsp;');
        }
    });

    // netmap show controls. Setting any force-graph prop repaints, so
    // re-setting nodeRelSize to itself is the repaint call.
    $('#nd_showips').change(function () {
      window.graph.fg.nodeRelSize(window.graph.fg.nodeRelSize());
    });
    $('#nd_showspeed').change(function () {
      window.graph.fg.nodeRelSize(window.graph.fg.nodeRelSize());
    });

    // netmap pin/release controls
    $('#nd_netmap-releaseall').on('click', function (event) {
      event.preventDefault();
      window.graph.fg.graphData().nodes.forEach(function (n) { n.fx = undefined; n.fy = undefined });
      window.graph.fg.d3ReheatSimulation();
    });
    $('#nd_netmap-releaseonly').on('click', function (event) {
      event.preventDefault();
      window.graph.fg.graphData().nodes.forEach(function (n) {
        if (n.selected) { n.fx = undefined; n.fy = undefined }
      });
      window.graph.fg.d3ReheatSimulation();
    });
    $('#nd_netmap-pinonly').on('click', function (event) {
      event.preventDefault();
      window.graph.fg.graphData().nodes.forEach(function (n) {
        if (n.selected) { n.fx = n.x; n.fy = n.y }
      });
    });
    $('#nd_netmap-zoomtodevice').on('click', function (event) {
      event.preventDefault();
      var n = window.graph.nodeDataById(window.graph.centernode);
      window.graph.fg.centerAt(n.x, n.y, 600);
      window.graph.fg.zoom(4, 600);
    });
    $('#nd_netmap-save').on('click', function (event) {
      event.preventDefault();
      // true marks this as the user asking, which is what netdisco-netmap.js
      // keys the confirmation toast off
      saveMapPositions(true);
    });

    // activity for admin tasks in device details
    $('#details_pane').on('click', '.nd_adminbutton', function(event) {
      // stop form from submitting normally
      event.preventDefault();

      // what purpose - discover/macsuck/arpnip
      var mode = $(this).attr('name');
      var tr = $(this).closest('tr');

      // submit the query
      $.ajax({
        type: 'POST'
        ,async: true
        ,dataType: 'html'
        ,url: uri_base + '/ajax/control/admin/' + mode
        ,data: tr.find('input[data-form="' + mode + '"],textarea[data-form="' + mode + '"]').serializeArray()
        ,success: function() {
          if (mode != 'delete') {
            toastr.info('Requested '+ mode +' for device '+ tr.data('for-device'));
            if (mode == 'snapshot_del') {
                $('.nd_snap_btn').toggleClass('btn-success');
                $('.nd_snap_btn').toggleClass('btn-info');
                $('.nd_snap_func').toggleClass('disabled');
            }
          }
          else {
            toastr.success('Queued job to delete '+ tr.data('for-device'));
          }
        }
        // skip any error reporting for now
        // TODO: fix sanity_ok in Netdisco Web
        ,error: function() {
          toastr.error('Failed to '+ mode +' device '+ tr.data('for-device'));
        }
      });
    });

    $('#details_pane').on('click', '.nd_nonadminbutton', function(event) {
      // stop form from submitting normally
      event.preventDefault();

      // what purpose - discover/macsuck/arpnip
      var mode = $(this).attr('name');
      var tr = $(this).closest('tr');

      // submit the query
      $.ajax({
        type: 'POST'
        ,async: true
        ,dataType: 'html'
        ,url: uri_base + '/ajax/control/nonadmin/' + mode
        ,data: tr.find('input[data-form="' + mode + '"],textarea[data-form="' + mode + '"]').serializeArray()
        ,success: function() {
          toastr.info('Requested '+ mode +' for device '+ tr.data('for-device'));
        }
        // skip any error reporting for now
        // TODO: fix sanity_ok in Netdisco Web
        ,error: function() {
          toastr.error('Failed to '+ mode +' device '+ tr.data('for-device'));
        }
      });
    });

    // clear any values in the delete confirm dialog
    $('#details_pane').on('hidden.bs.modal', '.nd_modal', function () {
      $('#nd_devdel-log').val('');
      $('#nd_devdel-archive').attr('checked', false);
    });
  }
  else if (page === 'search') {
    // fields in the Device Search Options form (Device tab)
    form_inputs = $("#device_form .clearfix input").not('[type="checkbox"]')
        .add("#device_form .clearfix select");

    // sidebar form fields should change colour and have bin/copy icon
    form_inputs.each(function() {device_form_state($(this))});
    form_inputs.change(function() {device_form_state($(this))});

    // handler for copy icon in search option
    $('.nd_field-copy-icon').click(function() {
      var name = $(this).data('btn-for');
      var input = $('#device_form [name=' + name + ']');
      input.val( $('#nq').val() );
      device_form_state(input); // will hide copy icons
    });

    // handler for bin icon in search option
    $('.nd_field-clear-icon').click(function() {
      var name = $(this).data('btn-for');
      var input = $('#device_form [name=' + name + ']');
      input.val('');
      device_form_state(input); // will hide copy icons
    });
  }
  else if (page === 'report') {
    // some reports carry bind params but no configured sidebar, so they
    // start with the sidebar already hidden; mirrors the manual toggle below
    if (document.querySelector('form[data-nd-hide-sidebar]')) {
      $('.nd_sidebar').toggle(0);
      $('#nd_sidebar-toggle-img-out').toggle();
      $('.content').css('margin-right', '10px');
      sidebar_hidden = 1;
    }

    // colored input fields in the Report Options sidebar forms
    form_inputs = $(".nd_colored-input");

    // sidebar form fields should change colour and have trash icon
    form_inputs.each(function() {device_form_state($(this))});
    form_inputs.change(function() {device_form_state($(this))});

    // handler for bin icon in search forms
    $('.nd_field-clear-icon').click(function() {
      var name = $(this).data('btn-for');
      var input = $('[name=' + name + ']');
      input.val('');
      device_form_state(input); // reset input field
    });

    $('#nd_ipinventory-subnet').on('input', function(event) {
      if ($(this).val().indexOf(':') != -1) {
        $('#never').attr('disabled', 'disabled');
      }
      else {
        $('#never').removeAttr('disabled');
      }
    });

    // dynamically bind to all forms in the table
    $('.content').on('click', '.nd_adminbutton', function(event) {
      // stop form from submitting normally
      event.preventDefault();

      // what purpose - add/update/del
      var mode = $(this).attr('name');

      // submit the query and put results into the tab pane
      $.ajax({
        type: 'POST'
        ,async: true
        ,dataType: 'html'
        ,url: uri_base + '/ajax/control/report/' + tab + '/' + mode
        ,data: $(this).closest('tr').find('input[data-form="' + mode + '"]').serializeArray()
        ,beforeSend: function() {
          $(target).html(
            '<div class="col-md-2 alert">Request submitted...</div>'
          );
        }
        ,success: function() {
          htmx.trigger('#' + tab + '_form', 'submit');
        }
        // skip any error reporting for now
        // TODO: fix sanity_ok in Netdisco Web
        ,error: function() {
          htmx.trigger('#' + tab + '_form', 'submit');
        }
      });
    });
  }
  else if (ndPages[page] && ndPages[page].ready) {
    form_inputs = ndPages[page].formInputs ? ndPages[page].formInputs() : $();
    ndPages[page].ready();
  }

  // Every sidebar form loads its own pane over htmx, declared by its hx-get.
  // This carries the side effects only and must not call preventDefault:
  // htmx's own submit listener does that.
  //
  // The csv and reset links used to be rebuilt here and now arrive with the
  // pane. What is left is what no response can answer: the navbar copy writes
  // into a form the response must never replace, and whether a tab has a
  // sidebar is declared by the sidebar templates rather than by any route.
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
  $('.nd_navtenant').click(function(event) {
    event.preventDefault();
    var url = new URL(window.location.href);
    var newpath = url.pathname;
    newpath = newpath.replace($(this).data('currenttenant'), "");
    newpath = newpath.replace(document.body.dataset.ndPath, "/");
    newpath = newpath.replace("//", "/");
    newpath = $(this).data('tenantpath').concat(newpath, url.search);
    window.location = newpath;
  });
});
