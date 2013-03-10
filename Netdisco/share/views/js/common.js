  $(document).ready(function() {
    // search hook for each tab
    [% FOREACH tab IN settings.search_tabs %]
    $('[% "#${tab.tag}_form" %]').submit(function(event){ do_search(event, '[% tab.tag %]'); });
    [% END %]
    [% FOREACH tab IN settings.device_tabs %]
    $('[% "#${tab.tag}_form" %]').submit(function(event){ do_search(event, '[% tab.tag %]'); });
    [% END %]

    // on page load, load the content for the active tab
    [% IF params.tab %]
    $('#[% params.tab %]_form').trigger("submit");
    [% END %]
  });
