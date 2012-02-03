  // this is called by do_search to support local code
  function inner_view_processing() {}

  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'search';

  $(document).ready(function() {
    // highlight active search filters in green.
    // strikethrough the navbar search if using device_form instead.

    var d_inputs = $("#device_form .clearfix input").not('[type="checkbox"]')
        .add("#device_form .clearfix select");

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

    d_inputs.each(function() {device_form_state($(this))});
    d_inputs.change(function() {device_form_state($(this))});
  });
