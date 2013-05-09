  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'admin';

  // this is called by do_search to support local code
  // which might need to act on the newly inserted content
  // but which cannot use jQuery delegation via .on()
  function inner_view_processing(tab) {

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
      $(this).siblings('.nd_topo_port').autocomplete('search') });


    // activity for admin task tables
    // dynamically bind to all forms in the table
    $(target).on('submit', 'form', function() {
      // stop form from submitting normally
      event.preventDefault();

      // submit the query and put results into the tab pane
      $.ajax({
        type: 'POST'
        ,async: true
        ,dataType: 'html'
        ,url: uri_base + '/ajax/content/admin/' + tab + '/' + $(this).attr('name')
        ,data: $(this).serializeArray()
        ,beforeSend: function() {
          $(target).html(
            '<div class="span2 alert">Waiting for results...</div>'
          );
        }
        ,success: function(content) {
          $('#' + tab + '_form').trigger('submit');
        }
        ,error: function() {
          $(target).html(
            '<div class="span5 alert alert-error">' +
            'Update failed! Please contact your site administrator.</div>'
          );
        }
      });
    });
  });
