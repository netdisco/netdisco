  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'search';

  // fields in the Device Search Options form (Device tab)
  var form_inputs = $("#device_form .clearfix input").not('[type="checkbox"]')
      .add("#device_form .clearfix select");

  // this is called by do_search to support local code
  // here, when tab changes need to strike/unstrike the navbar search
  function inner_view_processing(tab) {
  }

  // on load, check initial Device Search Options form state,
  // and on each change to the form fields
  $(document).ready(function() {
    // sidebar form fields should change colour and have bin/copy icon
    form_inputs.each(function() {device_form_state($(this))});
    form_inputs.change(function() {device_form_state($(this))});

    // handler for copy icon in search option
    $('.field_copy_icon').click(function() {
      var name = $(this).data('btn-for');
      var input = $('#device_form [name=' + name + ']');
      input.val( $('#nq').val() );
      device_form_state(input); // will hide copy icons
    });

    // handler for bin icon in search option
    $('.field_clear_icon').click(function() {
      var name = $(this).data('btn-for');
      var input = $('#device_form [name=' + name + ']');
      input.val('');
      device_form_state(input); // will hide copy icons
    });
  });
