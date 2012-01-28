    // parameterised for the active tab - submits search form and injects
    // HTML response into the tab pane, or an error/empty-results message
    function do_search (event, tab) {
      var form = '#' + tab + '_form';
      var target = '#' + tab + '_pane';
      var mark = '#' + tab + '_bookmark';

      // stop form from submitting normally
      event.preventDefault();

      // copy current search string to other forms' input box
      $('form').find("input[name=q]").each( function() {
        $(this).val( $(form).find("input[name=q]").val() );
      });

      // get the form params
      var query = $(form).serialize();

      if (window.History.enabled) {
        is_from_history_plugin = 1;
        window.History.replaceState(
          {name: tab, fields: $(form).serializeArray()},
          'Netdisco - '+ tab.charAt(0).toUpperCase() + tab.slice(1),
          '[% uri_for('/' _ path) %]?' + query
        );
        is_from_history_plugin = 0;
      }

      // in case of slow data load, let the user know
      $(target).html(
        '<div class="span3 alert-message notice"><p>Waiting for results...</p></div>'
      );

      // submit the query and put results into the tab pane
      $(target).load( '[% uri_for('/ajax/content/' _ path) %]/' + tab + '?' + query,
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
          $(mark).attr('href', '[% uri_for('/' _ path) %]?' + query);

          inner_view_processing();
        }
      );
    }

    // the history.js plugin is great, but fires statechange at pushState
    // so we have these semaphpores to help avoid messing the History.

    // set true when faking a user click on a tab
    var is_from_state_event = 0;
    // set true when the history plugin does pushState - to prevent loop
    var is_from_history_plugin = 0;

    // handler for ajax navigation
    if (window.History.enabled) { 
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

    // on tab change, hide previous tab's search form and show new tab's
    // search form. also trigger to load the content for the newly active tab.
    function update_content(from, to) {
      $('#' + from + '_search').toggleClass('active');
      $('#' + to + '_search').toggleClass('active');

      var to_form = '#' + to + '_form';
      var from_form = '#' + from + '_form';

      if (window.History.enabled && is_from_state_event == 0) {
        is_from_history_plugin = 1;
        window.History.pushState(
          {name: to, fields: $(to_form).serializeArray()},
          'Netdisco '+ $(to_form).find("input[name=ip]").val()  +' '+ to.charAt(0).toUpperCase() + to.slice(1),
          '[% uri_for('/' _ path) %]?' + $(to_form).serialize()
        );
        is_from_history_plugin = 0;
      }

      $(to_form).trigger("submit");
    }

    // could not get twitter bootstrap tabs to behave, so implemented this
    // but warning! will probably not work for dropdowns in tabs
    $('#search_results li').delegate('a', 'click', function(event) {
      event.preventDefault();
      var from_li = $('.tabs').find('> .active').first();
      var to_li = $(this).parent('li')

      from_li.removeClass('active');
      to_li.addClass('active');

      var from = from_li.find('a').attr('href');
      var to = $(this).attr('href');

      $(from).toggleClass('active');
      $(to).toggleClass('active');

      update_content(
        from.replace(/^#/,"").replace(/_pane$/,""),
        to.replace(/^#/,"").replace(/_pane$/,"")
      );
    });

    // search hook for each tab
    [% FOREACH tab IN vars.tabs %]
    $('[% "#${tab.id}_form" %]').submit(function(event){ do_search(event, '[% tab.id %]'); });
    [% END %]

    // on page load, load the content for the active tab
    [% IF params.tab %]
    $('#[% params.tab %]_form').trigger("submit");
    [% END %]

