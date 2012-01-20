  $(document).ready(function() {
    $('.nd_collapse_columns').collapser({
      target: 'next',
      effect: 'slide',
      changeText: true,
      expandHtml: '<label class="nd_collapser">Display Columns<div class="arrow-up"></div></label>',
      collapseHtml: '<label class="nd_collapser">Display Columns<div class="arrow-down"></div></label>',
    });

    $('.nd_collapse_portprop').collapser({
      target: 'next',
      effect: 'slide',
      changeText: true,
      expandHtml: '<label class="nd_collapser">Port Properties<div class="arrow-up"></div></label>',
      collapseHtml: '<label class="nd_collapser">Port Properties<div class="arrow-down"></div></label>',
    });

    $('.nd_collapse_nodeprop').collapser({
      target: 'next',
      effect: 'slide',
      changeText: true,
      expandHtml: '<label class="nd_collapser">Node Properties<div class="arrow-up"></div></label>',
      collapseHtml: '<label class="nd_collapser">Node Properties<div class="arrow-down"></div></label>',
    });

    $('.nd_collapse_legend').collapser({
      target: 'next',
      effect: 'slide',
      changeText: true,
      expandHtml: '<label class="nd_collapser">Legend<div class="arrow-up"></div></label>',
      collapseHtml: '<label class="nd_collapser">Legend<div class="arrow-down"></div></label>',
    });

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
      $(target).load( '[% uri_for('/ajax/content/device') %]/' + tab + '?' + query,
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
          $(mark).attr('href', '[% uri_for('/device') %]?' + query);

          // enable collapser on any large vlan lists
          $('.nd_collapse_vlans').collapser({
            target: 'next',
            effect: 'slide',
            changeText: true,
            expandHtml: '<div class="cell-arrow-up"></div><div class="nd_collapser">Show VLANs</div>',
            collapseHtml: '<div class="cell-arrow-down"></div><div class="nd_collapser">Hide VLANs</div>',
          });
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

    // sidebar toggle
    $('#sidebar_toggle_img_in').click(
      function() {
        $('.sidebar').toggle(
          function() {
            $('#sidebar_toggle_img_out').toggle();
            $('.nd_content').animate({'margin-left': '5px !important'}, 100);
          }
        );
      }
    );
    $('#sidebar_toggle_img_out').click(
      function() {
        $('#sidebar_toggle_img_out').toggle();
        $('.nd_content').animate({'margin-left': '225px !important'}, 200,
          function() { $('.sidebar').toggle(200) }
        );
      }
    );
  });
