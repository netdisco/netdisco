  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'search';

  // fields in the Device Search Options form (Device tab)
  var form_inputs = $("#device_form .clearfix input").not('[type="checkbox"]')
      .add("#device_form .clearfix select");

  // this is called by do_search to support local code
  // which might need to act on the newly inserted content
  // but which cannot use jQuery delegation via .on()
  function inner_view_processing(tab) {
  }

  // on load, establish global delegations for now and future
  $(document).ready(function() {
    var tab = '[% tab.tag | html_entity %]'
    var target = '#' + tab + '_pane';

    // sidebar form fields should change colour and have bin/copy icon
    form_inputs.each(function() {device_form_state($(this))});
    form_inputs.change(function() {device_form_state($(this))});

    // handler for copy icon in search option
    $('.nd_field-copy-icon').click(function() {
      var name = $(this).data('btn-for');
      var input = $('#device_form [name=' + name + ']');
      input.val( $('#nq').val() );
      device_form_state(input); // will hide copy icons
    });

    // handler for bin icon in search option
    $('.nd_field-clear-icon').click(function() {
      var name = $(this).data('btn-for');
      var input = $('#device_form [name=' + name + ']');
      input.val('');
      device_form_state(input); // will hide copy icons
    });
  });
