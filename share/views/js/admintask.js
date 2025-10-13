  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'admin';

  // keep track of timers so we can kill them
  var nd_timers  = new Array();
  var timermax   = [% settings.jobqueue_refresh || 5 | html_entity %];
  var timercache = timermax - 1;

  // this is called by do_search to support local code
  // which might need to act on the newly inserted content
  // but which cannot use jQuery delegation via .on()
  function inner_view_processing(tab) {

    // reload this table every 5 seconds
    if ((tab == 'jobqueue')
        && $('#nd_countdown-control-icon').hasClass('icon-play')) {

        $('#nd_countdown').text(timermax);

        // add new timers
        for (var i = timercache; i > 0; i--) {
          nd_timers.push(setTimeout(function() {
            $('#nd_countdown').text(timercache);
            timercache = timercache - 1;
          }, ((timermax * 1000) - (i * 1000)) ));
        }

        nd_timers.push(setTimeout(function() {
          // clear any running timers
          for (var i = 0; i < nd_timers.length; i++) {
              clearTimeout(nd_timers[i]);
          }

          // reset the timer cache
          timercache = timermax - 1;

          // reload the tab content in...
          $('#' + tab + '_form').trigger('submit');
        }, (timermax * 1000)));
    }

    // activate typeahead on the queue filter boxes
    $('.nd_queue_ta').autocomplete({
      source: function (request, response)  {
        var name = $(this.element)[0].name;
        var query = $(this.element).serialize();
        return $.get( uri_base + '/ajax/data/queue/typeahead/' + name, query, function (data) {
          return response(data);
        });
      }
      ,delay: 150
      ,minLength: 0
    });

    // activate typeahead on access control list editors
    $('.nd_acl_host_searcher').autocomplete({
      source: uri_base + '/ajax/data/devices/typeahead'
      ,select: function( event, ui ) {
        event.preventDefault();
        $(this).val(ui.item.value);
        $(this).trigger(jQuery.Event('keydown', { which: 13 }));
      }
      ,delay: 150
      ,minLength: 0
    });

    // activate typeahead on the topo boxes
    $('.nd_topo_dev').autocomplete({
      source: uri_base + '/ajax/data/deviceip/typeahead'
      ,delay: 150
      ,minLength: 0
    });

    // activate typeahead on the topo boxes
    $('.nd_topo_port.nd_topo_dev1').autocomplete({
      source: function (request, response)  {
        var query = $('.nd_topo_dev1').serialize();
        return $.get( uri_base + '/ajax/data/port/typeahead', query, function (data) {
          return response(data);
        });
      }
      ,delay: 150
      ,minLength: 0
    });

    // activate typeahead on the topo boxes
    $('.nd_topo_port.nd_topo_dev2').autocomplete({
      source: function (request, response)  {
        var query = $('.nd_topo_dev2').serialize();
        return $.get( uri_base + '/ajax/data/port/typeahead', query, function (data) {
          return response(data);
        });
      }
      ,delay: 150
      ,minLength: 0
    });

    $('.nd_jobqueue-extra').click(function(event) {
      event.preventDefault();
      var icon = $(this).children('i');
      $(icon).toggleClass('icon-plus');
      $(icon).toggleClass('icon-minus');
      var extra_id = $(this).data('extra');
      $('#' + extra_id).toggle();
    });

    // activate modals and tooltips
    $('.nd_modal').modal({show: false});
    $("[rel=tooltip]").tooltip({live: true});
  }

  // on load, establish global delegations for now and future
  $(document).ready(function() {
    var tab = '[% task.tag | html_entity %]'
    var target = '#' + tab + '_pane';

    // get autocomplete field on input focus
    $('.nd_sidebar').on('focus', '.nd_queue_ta', function(e) {
      $(this).autocomplete('search', '%') });
    $('.nd_sidebar').on('click', '.nd_topo_dev_caret', function(e) {
      $(this).siblings('.nd_queue_ta').autocomplete('search', '%') });

    // get all devices on device input focus
    $('.nd_sidebar').on('focus', '.nd_topo_dev', function(e) {
      $(this).autocomplete('search', '%') });
    $('.nd_sidebar').on('click', '.nd_topo_dev_caret', function(e) {
      $(this).siblings('.nd_topo_dev').autocomplete('search', '%') });

    // get all devices on device input focus
    $(target).on('focus', '.nd_acl_host_searcher', function(e) {
      $(this).autocomplete('search', '%') });
    $(target).on('focus', '.nd_topo_dev', function(e) {
      $(this).autocomplete('search', '%') });
    $(target).on('click', '.nd_topo_dev_caret', function(e) {
      $(this).siblings('.nd_topo_dev').autocomplete('search', '%') });

    // get all ports on port input focus
    $(target).on('focus', '.nd_topo_port', function(e) {
      $(this).autocomplete('search') });
    $(target).on('click', '.nd_topo_port_caret', function(e) {
      $(this).siblings('.nd_topo_port').val('');
      $(this).siblings('.nd_topo_port').autocomplete('search');
    });

    // job control sidebar submit should reset timer
    // and update bookmark
    $('#' + tab + '_submit').click(function(event) {
      for (var i = 0; i < nd_timers.length; i++) {
          clearTimeout(nd_timers[i]);
      }
      // reset the timer cache
      timercache = timermax - 1;

      // bookmark
      var querystr = $('#' + tab + '_form').serialize();
      $('#nd_jobqueue-bookmark').attr('href',uri_base + '/admin/' + tab + '?' + querystr);
    });

    // job control refresh icon should reload the page
    $('#nd_countdown-refresh').click(function(event) {
      event.preventDefault();
      for (var i = 0; i < nd_timers.length; i++) {
          clearTimeout(nd_timers[i]);
      }
      // reset the timer cache
      timercache = timermax - 1;
      // and reload content
      $('#' + tab + '_form').trigger('submit');
    });

    // job control pause/play icon switcheroo
    $('#nd_countdown-control').click(function(event) {
      event.preventDefault();
      var icon = $('#nd_countdown-control-icon');
      icon.toggleClass('icon-pause icon-play text-error text-success');

      if (icon.hasClass('icon-pause')) {
        for (var i = 0; i < nd_timers.length; i++) {
            clearTimeout(nd_timers[i]);
        }
        $('#nd_countdown').text('0');
      }
      else {
        $('#' + tab + '_form').trigger('submit');
      }
    });

    // activity for admin task tables
    // dynamically bind to all forms in the table
    $('.content').on('click', '.nd_adminbutton', function(event) {
      // stop form from submitting normally
      event.preventDefault();

      // clear any running timers
      for (var i = 0; i < nd_timers.length; i++) {
          clearTimeout(nd_timers[i]);
      }

      // what purpose - add/update/del
      var mode = $(this).attr('name');

      // admin task name with special case(s)
      var task = tab + '/';
      if (tab == 'duplicatedevices') {
        task = '';
      }

      // submit the query and put results into the tab pane
      $.ajax({
        type: 'POST'
        ,async: true
        ,dataType: 'html'
        ,url: uri_base + '/ajax/control/admin/' + task + mode
        ,data: $(this).closest('tr').find('input[data-form="' + mode + '"],select[data-form="' + mode + '"]').serializeArray()
        ,beforeSend: function() {
          if (mode == 'add' || mode == 'delete') {
            $(target).html(
              '<div class="span2 alert">Request submitted...</div>'
            );
          }
        }
        ,success: function() {
          if (mode == 'add') {
            toastr.success('Added record');
            $('#' + tab + '_form').trigger('submit');
          }
          else if (mode == 'delete') {
            toastr.success('Deleted record');
            $('#' + tab + '_form').trigger('submit');
          }
          else {
            toastr.success('Updated record');
          }
          $('#' + tab + '_form').trigger('submit');
        }
        // TODO: fix sanity_ok in Netdisco Web
        ,error: function() {
          if (mode == 'add') {
            toastr.error('Failed to add record');
            $('#' + tab + '_form').trigger('submit');
          }
          else if (mode == 'delete') {
            toastr.error('Failed to delete record');
            $('#' + tab + '_form').trigger('submit');
          }
          else {
            toastr.error('Failed to update record');
          }
        }
      });
    });

    // bind qtip2 to show the event log output
    $(target).on('mouseover', '.nd_jobqueueitem', function(event) {
      $(this).qtip({
        overwrite: false,
        content: {
          text: $('<span/>').text( $(this).attr("data-content") ).html()
        },
        show: {
          event: event.type,
          ready: true,
          delay: 100
        },
        position: {
          my: 'top center',
          at: 'bottom center',
          target: false
        },
        style: {
          classes: 'qtip-cluetip qtip-rounded nd_qtip-unconstrained'
        }
      });
    });
  });
