    // sidebar toggle
    $('#sidebar_toggle_img_in').click(
      function() {
        $('#sidebar_toggle_img_in').toggle();
        $('.sidebar').toggle(
          function() {
            $('#sidebar_toggle_img_out').toggle();
            $('.nd_content').animate({'margin-left': '5px !important'}, 100);
          }
        );
      }
    );
    $('#sidebar_toggle_img_out').click(
      function() {
        $('#sidebar_toggle_img_out').toggle();
        $('.nd_content').animate({'margin-left': '225px !important'}, 200,
          function() {
            $('.sidebar').toggle(200);
            $('#sidebar_toggle_img_in').toggle();
          }
        );
      }
    );
