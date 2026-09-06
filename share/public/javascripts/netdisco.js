// promoted from a <body> data attribute; the layout carries no inline
// JavaScript for CodeQL to skip.
var uri_base = document.body.dataset.ndUriBase;
var default_pgtitle = document.body.dataset.ndTitle;
var nd_check_userlog = (document.body.dataset.ndCheckUserlog === '1');

// parameterised for the active tab - submits search form and injects
// HTML response into the tab pane, or an error/empty-results message
// dispatch a real submit event so htmx, which listens natively, sees it.
// jQuery's trigger('submit') would instead end in form.submit(), a full page
// navigation that fires no submit listener at all. An untrusted event cannot
// cause native submission, so this only ever reaches listeners.
function nd_submit (form_selector) {
  var form = document.querySelector(form_selector);
  if (form) {
    form.dispatchEvent(new SubmitEvent('submit', {bubbles: true, cancelable: true}));
  }
}

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

// Nothing shipped calls this. It is here for site-local copies of
// share/views/js/common.js, which call it from their own submit handlers. It
// forwards with htmx.ajax() rather than nd_submit(), which would re-enter the
// caller's own submit handler and recurse.
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

// page, path and form_inputs are set from the active page's ready block
// further down (device, search, report or admin), and read as globals here
// and in inner_view_processing.
var page;
var path;
var form_inputs;
var sidebar_hidden = 0;

// admin jobqueue: keep track of timers so we can kill them
var nd_timers = new Array();
var timermax;
var timercache;

// set while replaying a history entry, so the tab click that replay fakes does
// not push a new entry for the tab it just restored
var is_from_state_event = 0;

// on tab change, hide previous tab's search form and show new tab's
// search form. also trigger to load the content for the newly active tab.
function update_content(from, to) {
  $('#' + from + '_search').toggleClass('active');
  $('#' + to + '_search').toggleClass('active');

  var to_form = '#' + to + '_form';
  var from_form = '#' + from + '_form';

  // Cancel a request still running for the tab being left. Its indicator sits
  // beside the pane rather than inside it, so the tab machinery cannot hide it
  // and it would stay on screen alongside the new tab's. Nothing is lost:
  // entering a tab always re-submits its form.
  var leaving = document.querySelector(from_form);
  if (leaving) { htmx.trigger(leaving, 'htmx:abort') }

  // page title
  var pgtitle = default_pgtitle;
  if ($('#nd_device-name').text().length) {
    var pgtitle = $.trim($('#nd_device-name').text()) +' - '+ $('#'+ to + '_link').text();
  }

  // navbar text decoration special case
  if (to != 'device') {
    $('#nq').css('text-decoration', 'none');
  }
  else {
    form_inputs.each(function() {device_form_state($(this))});
  }

  if (is_from_state_event == 0) {
    // pushState ignores its title argument, so set the title here and keep it
    // in the state for popstate to restore
    document.title = pgtitle;
    history.pushState(
      {name: to, fields: $(to_form).serializeArray(), title: pgtitle},
      '', uri_base + '/' + path + '?' + $(to_form).serialize()
    );
  }

  nd_submit(to_form);
}

// handler for ajax navigation
window.addEventListener('popstate', function (event) {
  // the first entry for a document carries no state
  if (!event.state) { return }

  is_from_state_event = 1;
  $('#'+ event.state.name + '_form').deserialize(event.state.fields);
  if (event.state.title) { document.title = event.state.title }
  $('#'+ event.state.name + '_link').click();
  is_from_state_event = 0;
});

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

//utility function for views
function capitalizeFirstLetter(string) {
    return string.charAt(0).toUpperCase() + string.slice(1);
}

// retitle a tooltip which is delegated from body. the delegate builds a
// per-element instance on first hover and caches it, so an existing
// instance must be disposed for the new title to be picked up.
function retitleTooltip(element, title) {
  $(element).attr('data-bs-title', title);
  var instance = bootstrap.Tooltip.getInstance($(element)[0]);
  if (instance) { instance.dispose(); }
}

// Hide an element that may be showing a tooltip, and any tooltip-carrying
// element inside it. Bootstrap dismisses a tip when the pointer leaves its
// trigger, but macOS Chrome fires no boundary event when the trigger is hidden
// under a pointer that has not moved, so nothing dismisses the tip and popper
// then anchors it to a zero sized rectangle at the window origin. Linux
// Chromium and Firefox both fire it, which is why #1667 only ever reproduced
// on a Mac and why leaving this to the mouseleave handler below is not enough.
function hideWithTooltip(target) {
  var elements = $(target);
  elements.find('[rel=tooltip]').addBack('[rel=tooltip]').each(function () {
    var instance = bootstrap.Tooltip.getInstance(this);
    if (instance) { instance.dispose(); }
  });
  elements.hide();
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

  // activate typeahead on the main search box, for device names only
  // the backend has already filtered, and jQuery UI does no client-side
  // filtering of a function source, so no matcher is needed
  $('#nq,#nqbody').autocomplete({
    source: function (request, response) {
      return $.get( uri_base + '/ajax/data/devicename/typeahead', request, function (data) {
        return response(data);
      });
    }
    ,delay: 150
    ,minLength: 3
    // the widget these boxes used to run opened with its first row picked out,
    // so Enter took the obvious name. jQuery UI selects nothing unless asked, and
    // does not write the row into the field: it only does that when a key moved
    // the focus.
    ,autoFocus: true
  });

  // Both boxes ran that widget, so both are marked and the blue highlight is
  // scoped to the mark; the app's other fifteen keep the theme's own.
  $('#nq,#nqbody').each(function() {
    $(this).autocomplete('widget').addClass('nd_search-suggestions');
  });

  // The navbar's box opens underneath the bar, and a menu hung at the field's
  // own edge starts its first row inside it. Four pixels rather than the three
  // that meet the edge exactly, the bar being a fraction taller on some
  // platforms. The whole object is restated because it replaces the default
  // rather than extending it, and losing collision:none would let the menu flip
  // above the field in a short window.
  $('#nq').autocomplete('option', 'position',
    { my: 'left top', at: 'left bottom+4', collision: 'none' });
  // Its border and padding still reach into the bar, which paints above this
  // widget's level, so the border needs lifting too. The menu is appended to the
  // document rather than beside its field, so marking the widget here is the only
  // way to reach one instance from the stylesheet.
  $('#nq').autocomplete('widget').addClass('nd_navbar-suggestions');

  // the widget this box used to run bolded the letters it matched, which is how
  // the list shows why each row is in it, and jQuery UI offers no equivalent.
  // Escaped first and marked second, because this goes in as markup where the
  // default went in as text and the names come from the database.
  $('#nq,#nqbody').each(function() {
    $(this).autocomplete('instance')._renderItem = function(ul, item) {
      var label = $('<div/>').text(item.label).html();
      var term = $('<div/>').text(this.term).html()
        .replace(/[\-\[\]{}()*+?.,\\\^$|#\s]/g, '\\$&');
      var marked = term.length
        ? label.replace(new RegExp('(' + term + ')', 'ig'), '<strong>$1</strong>')
        : label;
      return $('<li/>').append($('<div/>').html(marked)).appendTo(ul);
    };
  });

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
  syncCheckBox = function() {
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
    $('div.content > div.tab-content table.nd_floatinghead').floatThead('destroy');
    $('div.content > div.tab-content table.nd_floatinghead').floatThead({
      top: 40
      ,position: 'fixed'
    });
    sidebar_hidden = 1;
  });
  $('#nd_sidebar-toggle-img-out').click(function() {
    $('#nd_sidebar-toggle-img-out').toggle();
    $('.content').css('margin-right', '215px');
    $('div.content > div.tab-content table.nd_floatinghead').floatThead('destroy');
    $('div.content > div.tab-content table.nd_floatinghead').floatThead({
      top: 40
      ,position: 'fixed'
    });
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

  // admin ACL editor: the bin beside a rule removes the rule's label and its
  // input, then presses the row's update button. The button is found first
  // because the click removes the label the search would start from.
  document.addEventListener('click', function (event) {
    var bin = event.target.closest('.nd_delete-me');
    if (!bin) return;
    var row = bin.closest('tr');
    var button = row && row.querySelector('button.nd_adminbutton[name="update"]');
    var label = bin.closest('span.nd_left-acl-rule-label, span.nd_right-acl-rule-label');
    if (!label) return;
    var field = label.nextElementSibling;
    if (field && field.matches('input.nd_left-acl-rule-field, input.nd_right-acl-rule-field')) field.remove();
    label.remove();
    if (button) button.click();
  });

  // admin pseudo devices: the layer-3 badge toggles the hidden layers field
  // between "router" and "nothing".
  document.addEventListener('click', function (event) {
    var link = event.target.closest('.nd_layer-three-link');
    if (!link) return;
    var badge = link.querySelector('span');
    var layers = link.parentElement.querySelector('input');
    badge.classList.toggle('text-bg-success');
    layers.setAttribute('value', badge.classList.contains('text-bg-success') ? '00000100' : '00000000');
  });

  // admin users: the auth method select shows either the password field or
  // the token controls, per row. Guarded per element because the add row
  // carries no password field under no_auth and no token hint or button,
  // which a plain field lookup would otherwise throw on.
  function nd_token_fields(select) {
    var row = select.closest('tr');
    var pw = row.querySelector('.nd_pw_field');
    var cell = pw && pw.closest('td');
    var hint = row.querySelector('.nd_token_hint');
    var ips = row.querySelector('.nd_allowed_ips_field');
    var btn = row.querySelector('.nd_tokenbutton');
    var token = (select.value === 'permanent_token');
    if (pw) { pw.hidden = token; pw.disabled = token; if (token) pw.value = ''; else pw.placeholder = ''; }
    if (cell) { cell.classList.toggle('nd_center-middle-cell', token); cell.classList.toggle('nd_center-cell', !token) }
    if (hint) hint.hidden = !token;
    if (btn) btn.hidden = !token;
    if (ips) { ips.disabled = !token; if (!token) ips.value = '' }
  }
  document.addEventListener('change', function (event) {
    if (event.target.matches('.nd_auth_method')) nd_token_fields(event.target);
  });
  // Runs ahead of the htmx glue listener below, which builds the DataTable:
  // DataTables detaches rows outside the current page from the DOM, and this
  // sync must see every row while they are all still there.
  document.body.addEventListener('htmx:afterSwap', function (evt) {
    evt.detail.target.querySelectorAll('.nd_auth_method').forEach(nd_token_fields);
  });
  document.addEventListener('click', function (event) {
    var copy = event.target.closest('#nd_token-copy');
    if (!copy) return;
    navigator.clipboard.writeText(document.getElementById('nd_token-value').value);
    copy.innerHTML = '<i class="fas fa-check"></i> Copied';
  });

  // admin users: the key icon requests a fresh permanent token for a
  // token-only user. The route is declared with Dancer's ajax keyword, which
  // matches only a request carrying X-Requested-With: XMLHttpRequest; $.get
  // sent that automatically, fetch does not.
  document.addEventListener('click', function (event) {
    var btn = event.target.closest('.nd_tokenbutton');
    if (!btn) return;
    var hint = btn.closest('td').querySelector('.nd_token-hint-value');
    var query = new URLSearchParams({ username: btn.dataset.username, permanent: 1 });
    fetch(uri_base + '/ajax/control/admin/users/token?' + query,
      { headers: { 'X-Requested-With': 'XMLHttpRequest' } })
      .then(function (response) { return response.ok ? response.text() : Promise.reject() })
      .then(function (apiKey) {
        apiKey = apiKey.trim();
        if (apiKey && typeof window.nd_show_api_token === 'function') {
          hint.textContent = '...' + apiKey.slice(-8);
          window.nd_show_api_token(apiKey);
        } else {
          toastr.error('Could not retrieve token');
        }
      })
      .catch(function () { toastr.error('Could not retrieve token') });
  });

  // Called by admintask.js when the server returns a data-nd-api-key span
  window.nd_show_api_token = function(apiKey) {
    document.getElementById('nd_token-value').value = apiKey;
    document.getElementById('nd_token-copy').innerHTML = '<i class="fas fa-copy"></i> Copy';
    // Name the form rather than building its id from task.tag. This fragment
    // is only ever rendered by the ajax route in Users.pm, which passes no task
    // in its stash, so task.tag was always empty here and the selector was
    // always '#_form', which matches nothing. The tag is 'users' either way:
    // this template is registered for that one admin task.
    document.getElementById('nd_token-reveal').addEventListener('hidden.bs.modal', function() {
      nd_submit('#users_form');
    }, { once: true });
    bootstrap.Modal.getOrCreateInstance(document.getElementById('nd_token-reveal')).show();
  };

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

  // snmp tab: jsTree browser and its search box.
  function nd_snmp_browser(pane) {
    var device = pane.querySelector('#jstree').dataset.ndDevice;
    var jstree_search_callback = function(str, node) {
      var pattern = str.toLowerCase();
      var mib_pat = str.replace(/::.+/,'').toLowerCase();
      var leaf_pat = str.replace(/.+::/,'').toLowerCase();
      var mib_lc = node.original.mib.toLowerCase();
      var leaf_lc = node.original.leaf.toLowerCase();
      var oid = node.id.toLowerCase();

      if (document.getElementById('nd_snmp_search_deviceonly').checked) {
        if (node.original.has_value == 0) { return false; }
      }

      // partial is ticked, check OID base, or mib + leaf root, or just leaf
      if (document.getElementById('nd_snmp_search_partial').checked) {
        if (pattern.includes('.')) {
          if (oid.indexOf(pattern) == 0) { return true; }
        }
        else if (pattern.includes('::')) {
          if ((mib_lc == mib_pat) && (leaf_lc.indexOf(leaf_pat) == 0)) { return true; }
        }
        else if (leaf_lc.indexOf(pattern) == 0) {
          return true;
        }
      }
      // user supplies a qualified leaf
      else if (pattern.includes('::')) {
        if ((mib_lc == mib_pat) && (leaf_lc == leaf_pat)) {
          return true;
        }
      }
      // user supplies an unqualified leaf, or an OID
      else {
        if ((leaf_lc == pattern) || (oid == pattern)) {
          return true;
        }
      }
      return false;
    };

    $('#jstree').jstree({
      'core': {
        'multiple' : false,
        'themes': {
          'name': 'proton',
          'responsive': true
        },
        'data' : {
          'url' : function (node) {
            return (uri_base + '/ajax/data/device/' + device + '/snmptree/'
              + (node.id === '#' ? '.1' : node.id));
          }
        }
      },
      'plugins': ['search'],
      'search': {
        'ajax' : {
          'url' : uri_base + '/ajax/data/snmp/nodesearch',
          'beforeSend' : function(jqXHR, settings) {
            $('#nd_snmp_loading_spinner').removeClass('far fa-circle fas fa-circle-exclamation text-success')
                                         .addClass('fas fa-spinner text-warning fa-spin');

            if (document.getElementById('nd_snmp_search_partial').checked) {
              settings.url = settings.url + '&partial=on';
            }

            if (document.getElementById('nd_snmp_search_deviceonly').checked) {
              settings.url = settings.url + '&deviceonly=on&ip=' + device;
            }

            return true;
          },
          'error' : function() {
            $('#nd_snmp_loading_spinner').removeClass('fas fa-spinner text-warning fa-spin')
                                         .addClass('fas fa-circle-exclamation');
          }
        },
        'search_callback' : jstree_search_callback
      },
    });
    $('#snmpnodecontainer').on("change", "#munger", function(e, data) {
      var ary = $('#jstree').jstree('get_selected');
      $('#node').load(uri_base + '/ajax/content/device/' + device + '/snmpnode/'
        + ary[0] + '?munge=' + $('#munger').find(":selected").text());
    });
    $('#jstree').on("changed.jstree", function (e, data) {
      if (data.selected && data.selected != "#") {
        $('#node').load(uri_base + '/ajax/content/device/' + device + '/snmpnode/' + data.selected);
      }
    });
    $('#jstree').on("search.jstree", function (e, data) {
      if (data.res.length) {
        $('#node').load(uri_base + '/ajax/content/device/' + device + '/snmpnode/' + data.res[0]);

        $("#jstree").jstree().deselect_all(true);
        $('#jstree').jstree('select_node', data.res[0] + '_anchor');

        var node = $('#jstree').jstree("get_selected", true);
        var path = $('#jstree').jstree().get_path(node[0], false, true);
        var parent = path[path.length - 2];
        document.getElementById( parent ).scrollIntoView();

        $('#nd_snmp_loading_spinner').removeClass('fas fa-spinner text-warning fa-spin')
                                     .addClass('far fa-circle text-success');
      }
    });
    $("#nd_snmp_search_form").submit(function(e) {
      $("#jstree").jstree("search", $("#nd_snmp_search_text").val());
      e.preventDefault();
    });
    $('#nd_snmp_search_text').autocomplete({
      source: function (request, response)  {
        var query = $('.nd_snmp_search_param').serialize();
        return $.get( uri_base + '/ajax/data/snmp/typeahead', query, function (data) {
          return response(data);
        });
      }
      ,delay: 150
      ,minLength: 2
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

  // htmx glue. Converted panes get the same empty-result, error and
  // after-swap handling do_search gives the unconverted ones, so the two
  // transports are indistinguishable to a user. Keyed on any *_pane, not just
  // admin, because later rungs convert the search and device tabs onto this.
  document.body.addEventListener('htmx:afterSwap', function (evt) {
    var target = evt.detail.target;
    if (!target.id.match(/_pane$/)) return;
    var tab = target.id.replace(/_pane$/, '');
    if (target.innerHTML === '') {
      target.innerHTML =
        '<div class="col-md-2 alert alert-info">No matching records.</div>';
      return;
    }
    ndTables.init(target);
    if (target.querySelector('.tree')) nd_tree(target);
    if (target.querySelector('#jstree')) nd_snmp_browser(target);
    holdUntilSettled(target, document.getElementById(tab + '_indicator'));
    $('div.content > div.tab-content table.nd_floatinghead').floatThead({
      top: 40
      ,position: 'fixed'
    });
    inner_view_processing(tab);
  });
  // Empty the pane for the duration of the request, so the indicator is the
  // only thing on screen. Leaving the previous results up gives an interactive
  // table that no longer answers the search being run.
  //
  // jobqueue is excluded for the reason it carries no indicator: it refreshes
  // on a timer and would blank on every tick.
  document.body.addEventListener('htmx:beforeRequest', function (evt) {
    var target = evt.detail.target;
    if (!target.id.match(/_pane$/) || target.id === 'jobqueue_pane') return;

    // force-graph renders every frame until destroyed, and emptying the pane
    // only detaches its canvas. netmap.js destroys the previous instance as
    // well, but not until the new fragment's script runs.
    if (target.id === 'netmap_pane' && window.graph && window.graph.fg
        && typeof window.graph.fg._destructor === 'function') {
      window.graph.fg._destructor();
    }

    target.innerHTML = '';
  });
  document.body.addEventListener('htmx:responseError', function (evt) {
    var target = evt.detail.target;
    if (!target.id.match(/_pane$/)) return;
    target.innerHTML =
      '<div class="col-md-5 alert alert-danger"><i class="fas fa-triangle-exclamation"></i> ' +
      'Search failed! Please contact your site administrator (server error).</div>';
  });
  document.body.addEventListener('htmx:sendError', function (evt) {
    var target = evt.detail.target;
    if (!target.id.match(/_pane$/)) return;
    target.innerHTML =
      '<div class="col-md-5 alert alert-danger"><i class="fas fa-triangle-exclamation"></i> ' +
      'Search failed! Please contact your site administrator (network error).</div>';
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
  if (page === 'device') {
    // LT wanted the page title to reflect what's on the page :)
    document.title = $('#nd_device-name').text()
      +' - '+ $('#'+ tab + '_link').text();

    // used for contenteditable cells to find out whether the user has made
    // changes, and only reset when they submit or cancel the change
    var dirty = false;
  }
  else if (page === 'admin') {
    // reload this table every 5 seconds
    if ((tab == 'jobqueue')
        && $('#nd_countdown-control-icon').hasClass('fa-play')) {

        $('#nd_countdown').text(timermax);

        // add new timers
        for (var i = timercache; i > 0; i--) {
          nd_timers.push(setTimeout(function() {
            $('#nd_countdown').text(timercache);
            timercache = timercache - 1;
          }, ((timermax * 1000) - (i * 1000)) ));
        }

        nd_timers.push(setTimeout(function() {
          // clear any running timers
          for (var i = 0; i < nd_timers.length; i++) {
              clearTimeout(nd_timers[i]);
          }

          // reset the timer cache
          timercache = timermax - 1;

          // reload the tab content in...
          nd_submit('#' + tab + '_form');
        }, (timermax * 1000)));
    }

    // activate typeahead on the queue filter boxes
    $('.nd_queue_ta').autocomplete({
      source: function (request, response)  {
        var name = $(this.element)[0].name;
        var query = $(this.element).serialize();
        return $.get( uri_base + '/ajax/data/queue/typeahead/' + name, query, function (data) {
          return response(data);
        });
      }
      ,delay: 150
      ,minLength: 0
    });

    // activate typeahead on access control list editors
    $('.nd_acl_host_searcher').autocomplete({
      source: function (request, response)  {
        var query = $('.nd_sidebar-form').serializeArray();
        query.push($(this.element).serializeArray()[0]);
        return $.get( uri_base + '/ajax/data/devices/typeahead', query, function (data) {
          return response(data);
        });
      }
      ,select: function( event, ui ) {
        if (event.which == 13) { return };
        event.preventDefault();
        $(this).val(ui.item.value);
        $(this).trigger(jQuery.Event('keydown', { which: 13 }));
      }
      ,delay: 150
      ,minLength: 0
    });

    // activate typeahead on the topo boxes
    $('.nd_topo_dev').autocomplete({
      source: uri_base + '/ajax/data/deviceip/typeahead'
      ,delay: 150
      ,minLength: 0
    });

    // activate typeahead on the topo boxes
    $('.nd_topo_port.nd_topo_dev1').autocomplete({
      source: function (request, response)  {
        var query = $('.nd_topo_dev1').serialize();
        return $.get( uri_base + '/ajax/data/port/typeahead', query, function (data) {
          return response(data);
        });
      }
      ,delay: 150
      ,minLength: 0
    });

    // activate typeahead on the topo boxes
    $('.nd_topo_port.nd_topo_dev2').autocomplete({
      source: function (request, response)  {
        var query = $('.nd_topo_dev2').serialize();
        return $.get( uri_base + '/ajax/data/port/typeahead', query, function (data) {
          return response(data);
        });
      }
      ,delay: 150
      ,minLength: 0
    });

    $('.nd_jobqueue-extra').click(function(event) {
      event.preventDefault();
      var icon = $(this).children('i');
      $(icon).toggleClass('fa-plus');
      $(icon).toggleClass('fa-minus');
      var extra_id = $(this).data('extra');
      $('#' + extra_id).toggle();
    });
  }
  // search and report have nothing to do here now that tooltips and popovers
  // are delegated, but do_search and the htmx glue call this unconditionally.
}

// csv download icon on any table page
// needs to be dynamically updated to use current search options
function update_csv_download_link (type, tab, show) {
  var form = '#' + tab + '_form';
  var query = $(form).serialize();

  if (show.length) {
    $('#nd_csv-download')
      .attr('href', uri_base + '/ajax/content/' + type + '/' + tab + '?' + query)
      .attr('download', 'netdisco-' + type + '-' + tab + '.csv')
      .show();
  }
  else {
    hideWithTooltip('#nd_csv-download');
  }
}

// page title includes tab name and possibly device name
// this is nice for when you have multiple netdisco pages open in the
// browser
function update_page_title (tab) {
  var pgtitle = default_pgtitle;
  if ($.trim($('#nd_device-name').text()).length) {
    pgtitle = $.trim($('#nd_device-name').text()) +' - '+ $('#'+ tab + '_link').text();
  }
  return pgtitle;
}

// update browser search history with the new query.
// support history add (push) or replace via push parameter
function update_browser_history (tab, pgtitle, push) {
  var form = '#' + tab + '_form';
  var query = $(form).serialize();
  if (query.length) { query = '?' + query }

  // pushState and replaceState ignore their title argument, so set the title
  // beside each call and keep it in the state for popstate to restore
  var state = {name: tab, fields: $(form).serializeArray(), title: pgtitle};

  if (push.length) {
    var target = uri_base + '/' + path + '/' + tab + query;
    if (location.pathname == target) { return };
    document.title = pgtitle;
    history.pushState(state, '', target);
  }
  else {
    document.title = pgtitle;
    history.replaceState(state, '', uri_base + '/' + path + query);
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
  path = page;                                        // what update_content builds URLs from
  var activeForm = document.querySelector('.tab-pane.active form[data-nd-tab]');
  var tab = activeForm ? activeForm.dataset.ndTab : '';
  var target = '#' + tab + '_pane';

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
      nd_submit('#ports_form');
      device_form_state(portfilter); // will hide copy icons
    });

    // allow port filter to have a preference for port/name/vlan
    $('#ports_form').on('click', '.nd_device-port-submit-prefer', function() {
      event.preventDefault();
      $('#nd_ports-form-prefer-field').attr('value', $(this).data('prefer'));
      nd_submit('#ports_form');
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

      nd_submit('#ports_form');
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
      // true marks this as the user asking, which is what netmap.js keys the
      // confirmation toast off
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
      $('div.content > div.tab-content table.nd_floatinghead').floatThead('destroy');
      $('div.content > div.tab-content table.nd_floatinghead').floatThead({
        top: 40
        ,position: 'fixed'
      });
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

    // activate typeahead on prefix/subnet box
    $('#nd_ipinventory-subnet').autocomplete({
      source: function (request, response) {
        return $.get( uri_base + '/ajax/data/subnet/typeahead', request, function (data) {
          return response(data);
        });
      }
      ,delay: 150
      ,minLength: 3
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
          nd_submit('#' + tab + '_form');
        }
        // skip any error reporting for now
        // TODO: fix sanity_ok in Netdisco Web
        ,error: function() {
          nd_submit('#' + tab + '_form');
        }
      });
    });
  }
  else if (page === 'admin') {
    timermax = Number((activeForm && activeForm.dataset.ndJobqueueRefresh) || 5);
    timercache = timermax - 1;

    // get autocomplete field on input focus
    $('.nd_sidebar').on('focus', '.nd_queue_ta', function(e) {
      $(this).autocomplete('search', '%') });
    $('.nd_sidebar').on('click', '.nd_topo_dev_caret', function(e) {
      $(this).siblings('.nd_queue_ta').autocomplete('search', '%') });

    // get all devices on device input focus
    $('.nd_sidebar').on('focus', '.nd_topo_dev', function(e) {
      $(this).autocomplete('search', '%') });
    $('.nd_sidebar').on('click', '.nd_topo_dev_caret', function(e) {
      $(this).siblings('.nd_topo_dev').autocomplete('search', '%') });

    // get all devices on device input focus
    $(target).on('focus', '.nd_acl_host_searcher', function(e) {
      $(this).autocomplete('search', '%') });
    $(target).on('focus', '.nd_topo_dev', function(e) {
      $(this).autocomplete('search', '%') });
    $(target).on('click', '.nd_topo_dev_caret', function(e) {
      $(this).siblings('.nd_topo_dev').autocomplete('search', '%') });

    // get all ports on port input focus
    $(target).on('focus', '.nd_topo_port', function(e) {
      $(this).autocomplete('search') });
    $(target).on('click', '.nd_topo_port_caret', function(e) {
      $(this).siblings('.nd_topo_port').val('');
      $(this).siblings('.nd_topo_port').autocomplete('search');
    });

    // job control sidebar submit should reset timer
    // and update bookmark
    $('#' + tab + '_submit').click(function(event) {
      for (var i = 0; i < nd_timers.length; i++) {
          clearTimeout(nd_timers[i]);
      }
      // reset the timer cache
      timercache = timermax - 1;

      // bookmark
      var querystr = $('#' + tab + '_form').serialize();
      $('#nd_jobqueue-bookmark').attr('href',uri_base + '/admin/' + tab + '?' + querystr);
    });

    // job control refresh icon should reload the page
    $('#nd_countdown-refresh').click(function(event) {
      event.preventDefault();
      for (var i = 0; i < nd_timers.length; i++) {
          clearTimeout(nd_timers[i]);
      }
      // reset the timer cache
      timercache = timermax - 1;
      // and reload content
      nd_submit('#' + tab + '_form');
    });

    // job control pause/play icon switcheroo
    $('#nd_countdown-control').click(function(event) {
      event.preventDefault();
      var icon = $('#nd_countdown-control-icon');
      icon.toggleClass('fa-pause fa-play text-danger text-success');

      if (icon.hasClass('fa-pause')) {
        for (var i = 0; i < nd_timers.length; i++) {
            clearTimeout(nd_timers[i]);
        }
        $('#nd_countdown').text('0');
      }
      else {
        nd_submit('#' + tab + '_form');
      }
    });

    // activity for admin task tables
    // dynamically bind to all forms in the table
    $('.content').on('click', '.nd_adminbutton', function(event) {
      // stop form from submitting normally
      event.preventDefault();

      // clear any running timers
      for (var i = 0; i < nd_timers.length; i++) {
          clearTimeout(nd_timers[i]);
      }

      // what purpose - add/update/del
      var mode = $(this).attr('name');

      // admin task name with special case(s)
      var task = tab + '/';
      if (tab == 'duplicatedevices') {
        task = '';
      }

      // submit the query and put results into the tab pane
      $.ajax({
        type: 'POST'
        ,async: true
        ,dataType: 'html'
        ,url: uri_base + '/ajax/control/admin/' + task + mode
        ,data: $(this).closest('tr').find('input[data-form="' + mode + '"],select[data-form="' + mode + '"]').serializeArray()
        ,beforeSend: function() {
          if (mode == 'add' || mode == 'delete') {
            $(target).html(
              '<div class="col-md-2 alert">Request submitted...</div>'
            );
          }
        }
        ,success: function(data) {
          var apiKey = $(data).filter('[data-nd-api-key]').attr('data-nd-api-key');
          if (apiKey && typeof window.nd_show_api_token === 'function') {
            window.nd_show_api_token(apiKey);
            nd_submit('#' + tab + '_form');
            return;
          }
          if (mode == 'add') {
            toastr.success('Added record');
            nd_submit('#' + tab + '_form');
          }
          else if (mode == 'delete') {
            toastr.success('Deleted record');
            nd_submit('#' + tab + '_form');
          }
          else {
            toastr.success('Updated record');
          }
          nd_submit('#' + tab + '_form');
        }
        // TODO: fix sanity_ok in Netdisco Web
        ,error: function() {
          if (mode == 'add') {
            toastr.error('Failed to add record');
            nd_submit('#' + tab + '_form');
          }
          else if (mode == 'delete') {
            toastr.error('Failed to delete record');
            nd_submit('#' + tab + '_form');
          }
          else {
            toastr.error('Failed to update record');
          }
        }
      });
    });

    // show the event log output on hover, delegated from the pane so that rows
    // the table redraws are covered without re-initialising. the rows carry
    // their log in data-content, which the backend writes and bootstrap does
    // not read, so the content comes from a callback rather than renaming the
    // attribute. html is left off, so the log is inserted as text.
    new bootstrap.Popover(target, {
      selector: '.nd_jobqueueitem',
      content: function() { return this.getAttribute('data-content'); },
      trigger: 'hover',
      placement: 'bottom',
      delay: { show: 100, hide: 0 },
      customClass: 'nd_jobqueue-popover'
    });
  }

  // Every sidebar form loads its own pane over htmx, declared by its hx-get.
  // This carries the side effects only and must not call preventDefault:
  // htmx's own submit listener does that.
  document.addEventListener('submit', function (event) {
    var form = event.target;
    if (!form.matches('form[data-nd-tab]')) return;
    var tab = form.dataset.ndTab;
    var page = document.body.dataset.ndPage;
    var pgtitle = update_page_title(tab);
    if (page === 'search' || page === 'device') copy_navbar_to_sidebar(tab);
    if (page !== 'admin') update_browser_history(tab, pgtitle, page === 'report' ? '1' : '');
    update_csv_download_link(page, tab, form.dataset.ndCsv === '1' ? '1' : '');
    if (page === 'device' && tab === 'ports') {
      document.getElementById('nd_sidebar-reset-link').href = uri_base + '/device?tab=ports&reset=on&firstsearch=on&'
        + $('#ports_form').find('input[name="q"],input[name="f"],input[name="partial"],input[name="invert"]').serialize();
    }
    if (page === 'device' && tab === 'netmap') {
      document.getElementById('nd_sidebar-reset-link').href = uri_base + '/device?tab=netmap&reset=on&firstsearch=on&'
        + $('#netmap_form').find('input[name="q"]').serialize();
    }
    nd_apply_sidebar(tab);
  });

  // on page load, load the content for the active tab
  var active = document.body.dataset.ndActiveTab;
  if (active) {
    if (active === 'ipinventory' || active === 'subnets') document.getElementById(active + '_submit').click();
    else nd_submit('#' + active + '_form');
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
