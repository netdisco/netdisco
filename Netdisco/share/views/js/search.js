  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'search';

  // fields in the Device Search Options form (Device tab)
  var d_inputs = $("#device_form .clearfix input").not('[type="checkbox"]')
      .add("#device_form .clearfix select");

  // if any field in Device Search Options has content, highlight in green
  // and strikethrough the navbar search
  function device_form_state(e) {
    if (e.is('[value!=""]')) {
      if (e.attr('type') == 'text') {
        $('.field_copy_icon').hide();
      }

      e.parent(".clearfix").addClass('success');
      $('#nq').css('text-decoration', 'line-through');

      var id = '#' + e.attr('name') + '_clear_btn';
      $(id).show();
    }
    else {
      e.parent(".clearfix").removeClass('success');
      var id = '#' + e.attr('name') + '_clear_btn';
      $(id).hide();

      if (! d_inputs.is('[value!=""]') ) {
        $('#nq').css('text-decoration', 'none');
        $('.field_copy_icon').show();
      }
    }
  }

  // this is called by do_search to support local code
  // here, when tab changes need to strike/unstrike the navbar search
  function inner_view_processing(tab) {
    if (tab == 'device') {
      d_inputs.each(function() {device_form_state($(this))});
    }
    else {
      $('#nq').css('text-decoration', 'none');
    }
  }

  // on load, check initial Device Search Options form state,
  // and on each change to the form fields
  $(document).ready(function() {
    $('.field_copy_icon').hide();
    $('.field_clear_icon').hide();

    d_inputs.each(function() {device_form_state($(this))});
    d_inputs.change(function() {device_form_state($(this))});

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
      device_form_state(input);
    });
  });
