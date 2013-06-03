  $(document).ready(function() {
    // search tabs
    [% FOREACH tab IN settings._search_tabs %]
    $('[% "#${tab.tag}_form" %]').submit(function(event){ do_search(event, '[% tab.tag %]'); });
    [% END %]

    // device tabs
    [% FOREACH tab IN settings._device_tabs %]
    $('[% "#${tab.tag}_form" %]').submit(function(event){ do_search(event, '[% tab.tag %]'); });
    [% END %]

    [% IF report %]
    // for the report pages
    $('[% "#${report.tag}_form" %]').submit(function(event){ do_search(event, '[% report.tag %]'); });
    [% END -%]

    [% IF task %]
    // for the admin pages
    $('[% "#${task.tag}_form" %]').submit(function(event){ do_search(event, '[% task.tag %]'); });
    [% END %]

    // on page load, load the content for the active tab
    [% IF params.tab %]
    $('#[% params.tab %]_form').trigger("submit");
    [% END %]
  });
