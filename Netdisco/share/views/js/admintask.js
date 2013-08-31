  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'admin';

  // keep track of timers so we can kill them
  var nd_timers = new Array();

  // this is called by do_search to support local code
  // which might need to act on the newly inserted content
  // but which cannot use jQuery delegation via .on()
  function inner_view_processing(tab) {

    // reload this table every 5 seconds
    if (tab == 'jobqueue'
        && $('#nd_countdown-control-icon').hasClass('icon-play')) {

        $('#nd_countdown').text('5');
        nd_timers.push(setTimeout(function() { $('#nd_countdown').text('4') }, 1000 ));
        nd_timers.push(setTimeout(function() { $('#nd_countdown').text('3') }, 2000 ));
        nd_timers.push(setTimeout(function() { $('#nd_countdown').text('2') }, 3000 ));
        nd_timers.push(setTimeout(function() { $('#nd_countdown').text('1') }, 4000 ));
        nd_timers.push(setTimeout(function() {
          // clear any running timers
          for (var i = 0; i < nd_timers.length; i++) {
              clearTimeout(nd_timers[i]);
          }
          // reload the tab content
          $('#' + tab + '_form').trigger('submit');
        }, 5000));
    }

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

    // activate modals
    $('.nd_modal').modal({show: false});
  }

  // on load, establish global delegations for now and future
  $(document).ready(function() {
    var tab = '[% task.tag %]'
    var target = '#' + tab + '_pane';

    // get all devices on device input focus
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

    // job control refresh icon should reload the page
    $('#nd_countdown-refresh').click(function(event) {
      event.preventDefault();
      for (var i = 0; i < nd_timers.length; i++) {
          clearTimeout(nd_timers[i]);
      }
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

      // submit the query and put results into the tab pane
      $.ajax({
        type: 'POST'
        ,async: true
        ,dataType: 'html'
        ,url: uri_base + '/ajax/control/admin/' + tab + '/' + mode
        ,data: $(this).closest('tr').find('input[data-form="' + mode + '"]').serializeArray()
        ,beforeSend: function() {
          $(target).html(
            '<div class="span2 alert">Request submitted...</div>'
          );
        }
        ,success: function() {
          $('#' + tab + '_form').trigger('submit');
        }
        // skip any error reporting for now
        // TODO: fix sanity_ok in Netdisco Web
        ,error: function() {
          $('#' + tab + '_form').trigger('submit');
        }
      });
    });

    // bind qtip2 to show the event log output
    $(target).on('mouseover', '.nd_jobqueueitem', function(event) {
      $(this).qtip({
        overwrite: false,
        content: {
          attr: 'data-content'
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
