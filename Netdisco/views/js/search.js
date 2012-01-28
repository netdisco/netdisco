  $(document).ready(function() {
    // fix green background on search checkboxes
    // https://github.com/twitter/bootstrap/issues/742
    syncCheckBox = function() {
      $(this).parents('.add-on').toggleClass('active', $(this).is(':checked'));
    };
    $('.add-on :checkbox').each(syncCheckBox).click(syncCheckBox);

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

    function inner_view_processing() {} // noop

[%+ INCLUDE 'js/tabs.js' path="search" -%]
[%+ INCLUDE 'js/sidebar.js' -%]
[%+ INCLUDE 'js/fixes.js' -%]
  });
