  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'report';

  // fields in the IP Inventory Report form
  var form_inputs = $(".nd_colored-input");

  // this is called by do_search to support local code
  // here, when tab changes need to strike/unstrike the navbar search
  function inner_view_processing(tab) {

    // activate modals, tooltips and popovers
    $('.nd_modal').modal({show: false});
    $("[rel=tooltip]").tooltip({live: true});
    $("[rel=popover]").popover({live: true});
  }

  // on load, check initial Device Search Options form state,
  // and on each change to the form fields
  $(document).ready(function() {
    var tab = '[% report.tag %]'
    var target = '#' + tab + '_pane';

    // sidebar form fields should change colour and have trash icon
    form_inputs.each(function() {device_form_state($(this))});
    form_inputs.change(function() {device_form_state($(this))});

    $('#nd_ipinventory-subnet').on('input', function(event) {
      if ($(this).val().indexOf(':') != -1) {
        $('#never').attr('disabled', 'disabled');
      }
      else {
        $('#never').removeAttr('disabled');
      }
    });

    // activate typeahead on prefix/subnet box
    $('#nd_ipinventory-subnet').typeahead({
      source: function (query, process) {
        return $.get( uri_base + '/ajax/data/subnet/typeahead', { query: query }, function (data) {
          return process(data);
        });
      }
      ,matcher: function () { return true; } // trust backend
      ,delay: 250
      ,minLength: 3
    });
  });
