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
      '<div class="span2 alert"><i class="icon-spinner icon-spin"></i> Waiting for results...</div>'
    );
  }

  // submit the query and put results into the tab pane
  fetch( uri_base + '/ajax/content/' + path + '/' + tab + '?' + query,
    { headers: { 'X-Requested-With': 'XMLHttpRequest' } })
    .then( response => {
      if (! response.ok) {
        $(target).html(
          '<div class="span5 alert alert-error"><i class="icon-warning-sign"></i> ' +
          'Search failed! Please contact your site administrator (server error).</div>'
        );
        return;
        // throw new Error('Network response was not ok');
      }
      return response.text();
    })
    .then( content => {
      if (content == "") {
        $(target).html('<div class="span2 alert alert-info">No matching records.</div>');
      }
      else {
        $(target).html(content);
        // delegate to any [device|search] specific JS code
        $('div.content > div.tab-content table.nd_floatinghead').floatThead({
          scrollingTop: 40
          ,useAbsolutePositioning: false
        });
        inner_view_processing(tab);
      }
    })
    .catch( error => {
      $(target).html(
        '<div class="span5 alert alert-error"><i class="icon-warning-sign"></i> ' +
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

$(document).ready(function() {
  // sidebar form fields should change colour and have bin/copy icon
  $('.nd_field-copy-icon').hide();
  $('.nd_field-clear-icon').hide();

  // activate typeahead on the main search box, for device names only
  $('#nq,#nqbody').typeahead({
    source: function (query, process) {
      return $.get( uri_base + '/ajax/data/devicename/typeahead', { query: query }, function (data) {
        return process(data);
      });
    }
    ,matcher: function () { return true; } // trust backend
    ,minLength: 3
  });

  // activate tooltips
  $("[rel=tooltip]").tooltip({live: true});

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
    $(this).parents('.add-on').toggleClass('active', $(this).is(':checked'));
  };
  $('.add-on :checkbox').each(syncCheckBox).click(syncCheckBox);

  // sidebar toggle - pinning
  $('.nd_sidebar-pin').click(function() {
    $('.nd_sidebar').toggleClass('nd_sidebar-pinned');
    $('.nd_sidebar-pin').toggleClass('nd_sidebar-pin-clicked');
    // update tooltip note for current state
    if ($('.nd_sidebar-pin').hasClass('nd_sidebar-pin-clicked')) {
      $('.nd_sidebar-pin').first().data('tooltip').options.title = 'Unpin Sidebar';
    }
    else {
      $('.nd_sidebar-pin').first().data('tooltip').options.title = 'Pin Sidebar';
    }
  });

  // sidebar toggle - trigger in/out on image click()
  $('#nd_sidebar-toggle-img-in').click(function() {
    $('.nd_sidebar').toggle(250);
    $('#nd_sidebar-toggle-img-out').toggle();
    $('.content').css('margin-right', '10px');
    $('div.content > div.tab-content table.nd_floatinghead').floatThead('destroy');
    $('div.content > div.tab-content table.nd_floatinghead').floatThead({
      scrollingTop: 40
      ,useAbsolutePositioning: false
    });
    sidebar_hidden = 1;
  });
  $('#nd_sidebar-toggle-img-out').click(function() {
    $('#nd_sidebar-toggle-img-out').toggle();
    $('.content').css('margin-right', '215px');
    $('div.content > div.tab-content table.nd_floatinghead').floatThead('destroy');
    $('div.content > div.tab-content table.nd_floatinghead').floatThead({
      scrollingTop: 40
      ,useAbsolutePositioning: false
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
    var from_li = $('.nav-tabs').find('> .active').first();
    var to_li = $(this).parent('li')

    from_li.toggleClass('active');
    to_li.toggleClass('active');

    var from_id = from_li.find('a').attr('href');
    var to_id = $(this).attr('href');

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
  $('.tab-pane').on('show', '.nd_modal', function () {
    $(this).toggleClass('nd_deep-horizon');
  });
  $('.tab-pane').on('hidden', '.nd_modal', function () {
    $(this).toggleClass('nd_deep-horizon');
  });

  // activate daterange plugin
  $('#daterange').daterangepicker({
    ranges: {
      'Today': [moment(), moment()]
      ,'Yesterday': [moment().subtract('days', 1), moment().subtract('days', 1)]
      ,'Last 7 Days': [moment().subtract('days', 6), moment()]
      ,'Last 30 Days': [moment().subtract('days', 29), moment()]
      ,'This Month': [moment().startOf('month'), moment().endOf('month')]
      ,'Last Month': [moment().subtract('month', 1).startOf('month'), moment().subtract('month', 1).endOf('month')]
    }
    ,minDate: '2004-01-01'
    ,showDropdowns: true
    ,timePicker: false
    ,opens: 'left'
    ,format: 'YYYY-MM-DD'
    ,separator: ' to '
  }
  ,function(start, end) {
    $('#daterange').trigger('input');
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
    "icon-list-ol icon-sort-by-attributes-alt icon-rotate-180"
  );
};

