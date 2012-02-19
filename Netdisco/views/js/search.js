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
      e.parent(".clearfix").addClass('success');
      $('#nq').css('text-decoration', 'line-through');
    }
    else {
      e.parent(".clearfix").removeClass('success');
      if (! d_inputs.is('[value!=""]') ) {
        $('#nq').css('text-decoration', 'none');
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
    d_inputs.each(function() {device_form_state($(this))});
    d_inputs.change(function() {device_form_state($(this))});
  });
