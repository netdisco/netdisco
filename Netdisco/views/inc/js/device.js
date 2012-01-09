  $(document).ready(function() {
    // parameterised for the active tab - submits search form and injects
    // HTML response into the tab pane, or an error/empty-results message
    function do_search (event, tab) {
      var form = '#' + tab + '_form';
      var target = '#' + tab + '_pane';
      var mark = '#' + tab + '_bookmark';

      // stop form from submitting normally
      event.preventDefault();

      // get the form params
      var query = $(form).serialize();

      // in case of slow data load, let the user know
      $(target).html(
        '<div class="span3 alert-message notice"><p>Waiting for results...</p></div>'
      );

      // submit the query and put results into the tab pane
      $(target).load( '/ajax/content/device/' + tab + '?' + query,
        function(response, status, xhr) {
          if (status !== "success") {
            $(target).html(
              '<div class="span6 alert-message error">' +
              '<p>Search failed! Please contact your site administrator.</p></div>'
            );
            return;
          }
          if (response === "") {
            $(target).html(
              '<div class="span3 alert-message info"><p>No matching records.</p></div>'
            );
          }
          // looks good, update the bookmark for this search
          $(mark).attr('href', '/device?' + query);
        }
      );
    }

    // search hook for each tab
    [% FOREACH tab IN vars.tabs %]
    $('[% "#${tab.id}_form" %]').submit(function(event){ do_search(event, '[% tab.id %]'); });
    [% END %]

    // on page load, load the content for the active tab
    [% IF params.tab %]
    $('#[% params.tab %]_form').trigger("submit");
    [% END %]

    // on tab change, hide previous tab's search form and show new tab's
    // search form. also trigger to load the content for the newly active tab.
    $('#search_results').bind('change', function(e) {
      var to = $(e.target).attr('href').replace(/^#/,"").replace(/_pane$/,"");
      var from = $(e.relatedTarget).attr('href').replace(/^#/,"").replace(/_pane$/,"");

      $('#' + from + '_search').toggleClass('active');
      $('#' + to + '_search').toggleClass('active');

      var to_form = '#' + to + '_form';
      var from_form = '#' + from + '_form';
      // copy current search string to new form's input box
      $(to_form).find("input[name=q]").val(
        $(from_form).find("input[name=q]").val()
      );
      $(to_form).trigger("submit");
    });

    // fix green background on search checkboxes
    // https://github.com/twitter/bootstrap/issues/742
    syncCheckBox = function() {
      $(this).parents('.add-on').toggleClass('active', $(this).is(':checked'));
    };
    $('.add-on :checkbox').each(syncCheckBox).click(syncCheckBox);
  });
