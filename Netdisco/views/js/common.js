  $(document).ready(function() {
    // search hook for each tab
    [% FOREACH tab IN vars.tabs %]
    $('[% "#${tab.id}_form" %]').submit(function(event){ do_search(event, '[% tab.id %]'); });
    [% END %]

    // on page load, load the content for the active tab
    [% IF params.tab %]
    $('#[% params.tab %]_form').trigger("submit");
    [% END %]

    // enable typeahead on the main search box, for device names only
    $('#nq').typeahead({
      source: function (query, process) {
        return $.get('/ajax/data/device/typeahead', { query: query }, function (data) {
          return process(data);
        });
      }
    });
  });
