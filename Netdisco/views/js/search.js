  // this is called by do_search to support local code
  function inner_view_processing() {}

  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'search';

  $(document).ready(function() {
    // highlight active search filters in green
    // there must be a way to factor this out to a func but my JS is weak :-/

    $("form .clearfix input").not("[name=q]").each(function() {
      if ($(this).val() === "") {
        $(this).parent(".clearfix").removeClass('success');
      } else {
        $(this).parent(".clearfix").addClass('success');
      }
    });
    $("form .clearfix input").not("[name=q]").change(function() {
      if ($(this).val() === "") {
        $(this).parent(".clearfix").removeClass('success');
      } else {
        $(this).parent(".clearfix").addClass('success');
      }
    });
    $("form .clearfix select").each(function() {
      if ($(this).find(":selected").length === 0) {
        $(this).parent(".clearfix").removeClass('success');
      } else {
        $(this).parent(".clearfix").addClass('success');
      }
    });
    $("form .clearfix select").change(function() {
      if ($(this).find(":selected").length === 0) {
        $(this).parent(".clearfix").removeClass('success');
      } else {
        $(this).parent(".clearfix").addClass('success');
      }
    });

  });
