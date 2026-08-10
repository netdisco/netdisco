// parameterised for the active tab - submits search form and injects
// HTML response into the tab pane, or an error/empty-results message
function do_search (event, tab) {
  var form   = '#' + tab + '_form';
  var target = '#' + tab + '_pane';
  var query  = $(form).serialize();

  // stop form from submitting normally
  event.preventDefault();

  // hide or show sidebars depending on previous state,
  // and whether the sidebar contains any content (detected by TT)
  if (has_sidebar[tab] == 0) {
    $('.nd_sidebar, #nd_sidebar-toggle-img-out').hide();
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

  // in case of slow data load, let the user know
  if (tab != 'jobqueue') {
    $(target).html(
      '<div class="col-md-2 alert"><i class="fas fa-spinner fa-spin"></i> Waiting for results...</div>'
    );
  }

  // submit the query and put results into the tab pane
  fetch( uri_base + '/ajax/content/' + path + '/' + tab + '?' + query,
    { headers: { 'X-Requested-With': 'XMLHttpRequest' } })
    .then( response => {
      if (! response.ok) {
        $(target).html(
          '<div class="col-md-5 alert alert-danger"><i class="fas fa-triangle-exclamation"></i> ' +
          'Search failed! Please contact your site administrator (server error).</div>'
        );
        return;
        // throw new Error('Network response was not ok');
      }
      return response.text();
    })
    .then( content => {
      if (content == "") {
        $(target).html('<div class="col-md-2 alert alert-info">No matching records.</div>');
      }
      else {
        $(target).html(content);
        // delegate to any [device|search] specific JS code
        $('div.content > div.tab-content table.nd_floatinghead').floatThead({
          top: 40
          ,position: 'fixed'
        });
        inner_view_processing(tab);
      }
    })
    .catch( error => {
      $(target).html(
        '<div class="col-md-5 alert alert-danger"><i class="fas fa-triangle-exclamation"></i> ' +
        'Search failed! Please contact your site administrator (network error: ' + error + ').</div>'
      );
      console.error('There has been a problem with your fetch operation:', error);
    });
}

// keep track of which tabs have a sidebar, for when switching tab
var has_sidebar = {};
var sidebar_hidden = 0;

// the history.js plugin is great, but fires statechange at pushState
// so we have these semaphpores to help avoid messing the History.

// set true when faking a user click on a tab
var is_from_state_event = 0;
// set true when the history plugin does pushState - to prevent loop
var is_from_history_plugin = 0;

// on tab change, hide previous tab's search form and show new tab's
// search form. also trigger to load the content for the newly active tab.
function update_content(from, to) {
  $('#' + from + '_search').toggleClass('active');
  $('#' + to + '_search').toggleClass('active');

  var to_form = '#' + to + '_form';
  var from_form = '#' + from + '_form';

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

  if (window.History && window.History.enabled && is_from_state_event == 0) {
    is_from_history_plugin = 1;
    window.History.pushState(
      {name: to, fields: $(to_form).serializeArray()},
      pgtitle, uri_base + '/' + path + '?' + $(to_form).serialize()
    );
    is_from_history_plugin = 0;
  }

  $(to_form).trigger("submit");
}

// handler for ajax navigation
if (window.History && window.History.enabled) {
  var History = window.History;
  History.Adapter.bind(window, "statechange", function() {
    if (is_from_history_plugin == 0) {
      is_from_state_event = 1;
      var State = History.getState();
      // History.log(State.data.name, State.title, State.url);
      $('#'+ State.data.name + '_form').deserialize(State.data.fields);
      $('#'+ State.data.name + '_link').click();
      is_from_state_event = 0;
    }
  });
}

// if any field in Search Options has content, highlight in green
function device_form_state(e) {
  var with_val = $.grep(form_inputs,
                        function(n,i) {return($(n).prop('value') != "")}).length;
  var with_text = $.grep(form_inputs.not('select'),
                          function(n,i) {return($(n).val() != "")}).length;

  if (e.prop('value') == "") {
    e.parent(".clearfix").removeClass('success');
    var id = '#' + e.attr('name') + '_clear_btn';
    $(id).hide();

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
    var id = '#' + e.attr('name') + '_clear_btn';
    $(id).show();

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

$(document).ready(function() {
  // sidebar form fields should change colour and have bin/copy icon
  $('.nd_field-copy-icon').hide();
  $('.nd_field-clear-icon').hide();

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
});

// temporarily disable datatables paging
// returns [current_page_length, current_page_index]
function dataTablesDisablePaging() {
  $.fn.dataTable.ext.search.pop();
  var plen = $('#dp-data-table').DataTable().page.len();
  var pnum = $('#dp-data-table').DataTable().page();
  $('#dp-data-table').DataTable().page.len(-1).draw(true);
  return [plen, pnum];
}

// restore the datatables pagination and page number
function dataTablesRestorePage(plen, pnum) {
  $('#dp-data-table').DataTable().page.len(plen).draw(true);
  $('#dp-data-table').DataTable().page(pnum).draw(false);
}

// install our row filter for datatables row group toggle
function dataTablesPushRowGroupVisibilityFilter() {
  $.fn.dataTable.ext.search.push(
    function(settings, data, dataIndex) {
        var row = $($('#dp-data-table').DataTable().row(dataIndex).node());
        if (! row.data('collapsed-group')) { return true; }
        return row.attr('data-is-collapsed') == 'false';
    }
  );
}

// onclick handler
// toggles visibility of a group of datatables rows
// clicked element has the group name as data-collapsed-group
var dataTablesRowGroupVisibilityToggle = function () {
  var groupname = $(this).data('collapsed-group');
  var [plen, pnum] = dataTablesDisablePaging();

  // groupname is not in a class selector due to port name characters
  $('tr.nd_collapsible').each(function(index) { 
      if ($(this).data('collapsed-group') == groupname) {
          if ($(this).attr('data-is-collapsed') == 'true') {
            $(this).attr('data-is-collapsed', 'false');
          }
          else {
            $(this).attr('data-is-collapsed', 'true');
          }
      }
  });

  dataTablesPushRowGroupVisibilityFilter();
  dataTablesRestorePage(plen, pnum);

  var icon = $(this).find('i');
  icon.toggleClass(
    "fa-list-ol fa-arrow-up-wide-short fa-rotate-180"
  );
};

