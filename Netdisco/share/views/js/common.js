  // csv download icon on any table page
  // needs to be dynamically updated to use current search options
  function update_csv_download_link (type, tab, show) {
    var form = '#' + tab + '_form';
    var query = $(form).serialize();

    if (show.length) {
      $('#nd_csv-download')
        .attr('href', '/ajax/content/' + type + '/' + tab + '?' + query)
        .attr('download', 'netdisco-' + type + '-' + tab + '.csv')
        .show();
    }
    else {
      $('#nd_csv-download').hide();
    }
  }

  // page title includes tab name and possibly device name
  // this is nice for when you have multiple netdisco pages open in the
  // browser
  function update_page_title (tab) {
    var pgtitle = 'Netdisco';
    if ($.trim($('#nd_device-name').text()).length) {
      pgtitle = $.trim($('#nd_device-name').text()) +' - '+ $('#'+ tab + '_link').text();
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
    [% IF search %]
    // search tabs
    [% FOREACH tab IN settings._search_tabs %]
    $('[% "#${tab.tag}_form" %]').submit(function (event) {
      var pgtitle = update_page_title('[% tab.tag %]');
      copy_navbar_to_sidebar('[% tab.tag %]');
      update_browser_history('[% tab.tag %]', pgtitle);
      update_csv_download_link('search', '[% tab.tag %]', '[% tab.provides_csv %]');
      do_search(event, '[% tab.tag %]');
    });
    [% END %]
    [% END %]

    [% IF device %]
    // device tabs
    [% FOREACH tab IN settings._device_tabs %]
    $('[% "#${tab.tag}_form" %]').submit(function (event) {
      var pgtitle = update_page_title('[% tab.tag %]');
      copy_navbar_to_sidebar('[% tab.tag %]');
      update_browser_history('[% tab.tag %]', pgtitle);
      update_csv_download_link('device', '[% tab.tag %]', '[% tab.provides_csv %]');

      [% IF tab.tag == 'ports' %]
      // to be fair I can't remember why we do this in JS and not from the app
      // perhaps because selecting form fields to go in the cookie is easier?
      var cookie = $('#ports_form').find('input,select')
        .not('#nd_port-query,input[name="q"],input[name="tab"]')
        .serializeArray();
      $('#ports_form').find('input[type="checkbox"]').map(function() {
        cookie.push({'name': 'columns', 'value': $(this).attr('name')});
      });
      $.cookie('nd_ports-form', $.param(cookie) ,{ expires: 365 });

      // form reset icon on ports tab
      $('#nd_sidebar-reset-link').attr('href', '/device?tab=ports&reset=on&' +
        $('#ports_form')
          .find('input[name="q"],input[name="f"],input[name="partial"],input[name="invert"]')
          .serialize())
      [% END %]

      do_search(event, '[% tab.tag %]');
    });
    [% END %]
    [% END %]

    [% IF report %]
    // for the report pages
    $('[% "#${report.tag}_form" %]').submit(function (event) {
      update_page_title('[% report.tag %]');
      update_csv_download_link('report', '[% report.tag %]', '1');
      do_search(event, '[% report.tag %]');
    });
    [% END -%]

    [% IF task %]
    // for the admin pages
    $('[% "#${task.tag}_form" %]').submit(function (event) {
      update_page_title('[% task.tag %]');
      update_csv_download_link('task', '[% task.tag %]', '1');
      do_search(event, '[% task.tag %]');
    });
    [% END %]

    // on page load, load the content for the active tab
    [% IF params.tab %]
    $('#[% params.tab %]_form').trigger("submit");
    [% END %]
  });
