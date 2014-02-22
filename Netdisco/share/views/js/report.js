  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'report';

  // colored input fields in the Report Options sidebar forms
  var form_inputs = $(".nd_colored-input");

  // this is called by do_search to support local code
  // here, when tab changes need to strike/unstrike the navbar search
  function inner_view_processing(tab) {

    // activate modals, tooltips and popovers
    $('.nd_modal').modal({show: false});
    $("[rel=tooltip]").tooltip({live: true});
    $("[rel=popover]").popover({live: true});
  }

  // on load, check initial Report Options form state,
  // and on each change to the form fields
  $(document).ready(function() {
    var tab = '[% report.tag %]'
    var target = '#' + tab + '_pane';

    // sidebar form fields should change colour and have trash icon
    form_inputs.each(function() {device_form_state($(this))});
    form_inputs.change(function() {device_form_state($(this))});

    // handler for bin icon in search forms
    $('.nd_field-clear-icon').click(function() {
      var name = $(this).data('btn-for');
      var input = $('[name=' + name + ']');
      input.val('');
      device_form_state(input); // reset input field
    });

    $('#nd_ipinventory-subnet').on('input', function(event) {
      if ($(this).val().indexOf(':') != -1) {
        $('#never').attr('disabled', 'disabled');
      }
      else {
        $('#never').removeAttr('disabled');
      }
    });

    // activate typeahead on prefix/subnet box
    $('#nd_ipinventory-subnet').autocomplete({
      source: function (request, response) {
        return $.get( uri_base + '/ajax/data/subnet/typeahead', request, function (data) {
          return response(data);
        });
      }
      ,delay: 150
      ,minLength: 3
    });
  });
