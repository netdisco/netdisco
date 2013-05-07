  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'admin';

  // this is called by do_search to support local code
  // here, when tab changes need to strike/unstrike the navbar search
  function inner_view_processing(tab) {
    var target = '#' + tab + '_pane';

    // activate typeahead on the topo boxes
    $('.nd_topo_dev').autocomplete({
      source: '/ajax/data/deviceip/typeahead'
      ,minLength: 0
    });

    // get all devices on device input focus
    $(".nd_topo_dev").on('focus', function(e) { $(this).autocomplete('search', '%') });
    $(".nd_topo_dev_caret").on('click', function(e) { $(this).siblings('.nd_topo_dev').autocomplete('search', '%') });

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
      ,minLength: 0
    });

    // get all ports on port input focus
    $(".nd_topo_port").on('focus', function(e) { $(this).autocomplete('search') });
    $(".nd_topo_port_caret").on('click', function(e) { $(this).siblings('.nd_topo_port').autocomplete('search') });

    // activity for admin task tables
    // dynamically bind to all forms in the table
    $(target).on('submit', 'form', function() {
      // stop form from submitting normally
      event.preventDefault();

      // submit the query and put results into the tab pane
      $.ajax({
        type: 'POST'
        ,async: false
        ,dataType: 'html'
        ,url: uri_base + '/ajax/content/admin/' + tab + '/' + $(this).attr('name')
        ,data: $(this).serializeArray()
        ,beforeSend: function() {
          $(target).html(
            '<div class="span2 alert">Waiting for results...</div>'
          );
        }
        ,success: function(content) {
          $(target).html(content);
        }
        ,error: function() {
          $(target).html(
            '<div class="span5 alert alert-error">' +
            'Update failed! Please contact your site administrator.</div>'
          );
        }
      });
    });
  }

  // on load, check initial Device Search Options form state,
  // and on each change to the form fields
  $(document).ready(function() { });
