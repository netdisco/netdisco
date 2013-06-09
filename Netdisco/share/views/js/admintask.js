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
    if (tab == 'jobqueue') {
        $('#nd_device-name').text('5');
        nd_timers.push(setTimeout(function() { $('#nd_device-name').text('4') }, 1000 ));
        nd_timers.push(setTimeout(function() { $('#nd_device-name').text('3') }, 2000 ));
        nd_timers.push(setTimeout(function() { $('#nd_device-name').text('2') }, 3000 ));
        nd_timers.push(setTimeout(function() { $('#nd_device-name').text('1') }, 4000 ));
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
      source: '/ajax/data/deviceip/typeahead'
      ,delay: 150
      ,minLength: 0
    });

    // activate typeahead on the topo boxes
    $('.nd_topo_port.nd_topo_dev1').autocomplete({
      source: function (request, response)  {
        var query = $('.nd_topo_dev1').serialize();
        return $.get('/ajax/data/port/typeahead', query, function (data) {
          return response(data);
        });
      }
      ,minLength: 0
    });

    // activate typeahead on the topo boxes
    $('.nd_topo_port.nd_topo_dev2').autocomplete({
      source: function (request, response)  {
        var query = $('.nd_topo_dev2').serialize();
        return $.get('/ajax/data/port/typeahead', query, function (data) {
          return response(data);
        });
      }
      ,delay: 150
      ,minLength: 0
    });
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


    // activity for admin task tables
    // dynamically bind to all forms in the table
    $(target).on('submit', 'form', function() {
      // stop form from submitting normally
      event.preventDefault();

      // clear any running timers
      for (var i = 0; i < nd_timers.length; i++) {
          clearTimeout(nd_timers[i]);
      }

      // submit the query and put results into the tab pane
      $.ajax({
        type: 'POST'
        ,async: true
        ,dataType: 'html'
        ,url: uri_base + '/ajax/control/admin/' + tab + '/' + $(this).attr('name')
        ,data: $(this).serializeArray()
        ,beforeSend: function() {
          $(target).html(
            '<div class="span2 alert">Request submitted...</div>'
          );
        }
        ,success: function(content) {
          $('#' + tab + '_form').trigger('submit');
        }
        ,error: function() {
          $(target).html(
            '<div class="span5 alert alert-error">' +
            'Request failed! Please contact your site administrator.</div>'
          );
        }
      });
    });
  });
