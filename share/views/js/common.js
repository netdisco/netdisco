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
      $('#nd_csv-download').hide();
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

    if (window.History && window.History.enabled) {
      is_from_history_plugin = 1;

      if (push.length) {
        var target = uri_base + '/' + path + '/' + tab + query;
        if (location.pathname == target) { return };
        window.History.pushState(
          {name: tab, fields: $(form).serializeArray()}, pgtitle, target
        );
      }
      else {
        var target = uri_base + '/' + path + query;
        window.History.replaceState(
          {name: tab, fields: $(form).serializeArray()}, pgtitle, target
        );
      }

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
      var pgtitle = update_page_title('[% tab.tag | html_entity %]');
      copy_navbar_to_sidebar('[% tab.tag | html_entity %]');
      update_browser_history('[% tab.tag | html_entity %]', pgtitle, '');
      update_csv_download_link('search', '[% tab.tag | html_entity %]', '[% tab.provides_csv | html_entity %]');
      do_search(event, '[% tab.tag | html_entity %]');
    });
    [% END %]
    [% END %]

    [% IF device %]
    // device tabs
    [% FOREACH tab IN settings._device_tabs %]
    $('[% "#${tab.tag}_form" %]').submit(function (event) {
      var pgtitle = update_page_title('[% tab.tag | html_entity %]');
      copy_navbar_to_sidebar('[% tab.tag | html_entity %]');
      update_browser_history('[% tab.tag | html_entity %]', pgtitle, '');
      update_csv_download_link('device', '[% tab.tag | html_entity %]', '[% tab.provides_csv | html_entity %]');

      [% IF tab.tag == 'ports' %]
      // form reset icon on ports tab
      $('#nd_sidebar-reset-link').attr('href', uri_base + '/device?tab=[% tab.tag | html_entity %]&reset=on&firstsearch=on&' +
        $('#ports_form')
          .find('input[name="q"],input[name="f"],input[name="partial"],input[name="invert"]')
          .serialize());

      [% ELSIF tab.tag == 'netmap' %]
      // form reset icon on netmap tab
      $('#nd_sidebar-reset-link').attr('href', uri_base + '/device?tab=[% tab.tag | html_entity %]&reset=on&firstsearch=on&' +
        $('#netmap_form').find('input[name="q"]').serialize());
      [% END %]

      do_search(event, '[% tab.tag | html_entity %]');
    });
    [% END %]
    [% END %]

    [% IF report %]
    // for the report pages
    $('[% "#${report.tag}_form" %]').submit(function (event) {
      var pgtitle = update_page_title('[% report.tag | html_entity %]');
      update_browser_history('[% report.tag | html_entity %]', pgtitle, '1');
      update_csv_download_link('report', '[% report.tag | html_entity %]', '1');
      do_search(event, '[% report.tag | html_entity %]');
    });
    [% END -%]

    [% IF task %]
    // for the admin pages
    $('[% "#${task.tag}_form" %]').submit(function (event) {
      update_page_title('[% task.tag | html_entity %]');
      update_csv_download_link('admin', '[% task.tag | html_entity %]', '1');
      do_search(event, '[% task.tag | html_entity %]');
    });
    [% END %]

    // on page load, load the content for the active tab
    [% IF params.tab %]
    [% IF params.tab == 'ipinventory' OR params.tab == 'subnets' %]
      $('#[% params.tab | html_entity %]_submit').click();
    [% ELSE %]
      $('#[% params.tab | html_entity %]_form').trigger("submit");
    [% END %]
    [% END %]
  });
