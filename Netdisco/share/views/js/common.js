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
    var pgtitle = 'Netdisco';
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
      var target = uri_base + '/' + path + '/' + tab + query;

      if (push.length) {
        if (location.pathname == target) { return };
        window.History.pushState(
          {name: tab, fields: $(form).serializeArray()}, pgtitle, target
        );
      }
      else {
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
    // on page load, load the content for the active tab
    [% IF tabname %]
    [% IF tabname == 'ipinventory' OR tabname == 'subnets' %]
      $('#[% tabname %]_submit').click();
    [% ELSE %]
      $('#[% tabname %]_form').trigger("submit");
    [% END %]
    [% END %]
  });
