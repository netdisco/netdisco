  function update_page_title (tab) {
    var pgtitle = 'Netdisco';
    if ($('#nd_device-name').text().length) {
      var pgtitle = $('#nd_device-name').text() +' - '+ $('#'+ tab + '_link').text();
    }
    return pgtitle;
  }

  // update browser search history with the new query.
  // however if it's the same tab, this is a *replace* of the query url.
  // and just skip this bit if it's the report or admin display.
  function update_browser_history (tab, pgtitle) {
    var form = '#' + tab + '_form';
    var query = $(form).serialize();

    if (window.History && window.History.enabled) {
      is_from_history_plugin = 1;
      window.History.replaceState(
        {name: tab, fields: $(form).serializeArray()},
        pgtitle, uri_base + '/' + path + '?' + query
      );
      is_from_history_plugin = 0;
    }
  }

  // each sidebar search form has a hidden copy of the main navbar search
  // query. when the tab query takes place, copy the navbar locally, then
  // replicate to all other tabs.
  function copy_navbar_to_sidebar (tab) {
    var form = '#' + tab + '_form';

    if ($('#nq').val()) {
      $(form).find("input[name=q]").val( $('#nq').val() );
    }
    $('form').find("input[name=q]").each( function() {
      $(this).val( $(form).find("input[name=q]").val() );
    });
  }

  $(document).ready(function() {
    [% IF search %]
    // search tabs
    [% FOREACH tab IN settings._search_tabs %]
    $('[% "#${tab.tag}_form" %]').submit(function (event) {
      var pgtitle = update_page_title('[% tab.tag %]');
      update_browser_history('[% tab.tag %]', pgtitle);
      copy_navbar_to_sidebar('[% tab.tag %]');
      do_search(event, '[% tab.tag %]');
    });
    [% END %]
    [% END %]

    [% IF device %]
    // device tabs
    [% FOREACH tab IN settings._device_tabs %]
    $('[% "#${tab.tag}_form" %]').submit(function (event) {
      var pgtitle = update_page_title('[% tab.tag %]');
      update_browser_history('[% tab.tag %]', pgtitle);
      copy_navbar_to_sidebar('[% tab.tag %]');
      [% IF tab.tag == 'ports' %]
      var cookie = $('#ports_form').find('input,select')
        .not('#nd_port-query,input[name="q"],input[name="tab"]')
        .serializeArray();
      $('#ports_form').find('input[type="checkbox"]').map(function() {
        cookie.push({'name': 'columns', 'value': $(this).attr('name')});
      });
      $.cookie('nd_ports-form', $.param(cookie) ,{ expires: 365 });
      [% END %]
      do_search(event, '[% tab.tag %]');
    });
    [% END %]
    [% END %]

    [% IF report %]
    // for the report pages
    $('[% "#${report.tag}_form" %]').submit(function (event) {
      update_page_title('[% tab.tag %]');
      do_search(event, '[% report.tag %]');
    });
    [% END -%]

    [% IF task %]
    // for the admin pages
    $('[% "#${task.tag}_form" %]').submit(function (event) {
      update_page_title('[% tab.tag %]');
      do_search(event, '[% task.tag %]');
    });
    [% END %]

    // on page load, load the content for the active tab
    [% IF params.tab %]
    $('#[% params.tab %]_form').trigger("submit");
    [% END %]
  });
