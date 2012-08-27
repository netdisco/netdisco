  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'device';

  function inner_view_processing() {
    // VLANs column list collapser trigger
    // it's a bit of a faff because we can't easily use Bootstrap's collapser
    $('.nd_collapse_vlans').toggle(function() {
        event.preventDefault(); // prevent jump to top of page
        $(this).siblings('.nd_collapsing').toggle('fast');
        $(this).siblings('.cell-arrow-up').toggleClass('cell-arrow-down cell-arrow-up');
        $(this).html('<div class="cell-arrow-down"></div>Hide VLANs');
      }, function() {
        event.preventDefault(); // prevent jump to top of page
        $(this).siblings('.nd_collapsing').toggle('fast');
        $(this).siblings('.cell-arrow-down').toggleClass('cell-arrow-down cell-arrow-up');
        $(this).html('<div class="cell-arrow-up"></div>Show VLANs');
    });
  }

  $(document).ready(function() {
    // sidebar collapser events trigger change of up/down arrow
    $('.collapse').on('show', function() {
      $(this).siblings().find('.arrow-up').toggleClass('arrow-down arrow-up');
    });

    $('.collapse').on('hide', function() {
      $(this).siblings().find('.arrow-down').toggleClass('arrow-down arrow-up');
    });

    // show or hide sweeping brush icon when field has content
    var sweep = $('#ports_form').find("input[name=f]");

    if (sweep.val() === "") {
      $('.field_clear_icon').hide();
    } else {
      $('.field_clear_icon').show();
    }

    sweep.change(function() {
      if ($(this).val() === "") {
        $('.field_clear_icon').hide();
      } else {
        $('.field_clear_icon').show();
      }
    });

    // handler for sweeping brush icon in port filter box
    $('.field_clear_icon').click(function() {
      sweep.val('');
      $('.field_clear_icon').hide();
      $('#ports_form').trigger('submit');
    });

    // clickable device port names can simply resubmit AJAX rather than
    // fetch the whole page again.
    $('body').on('click', '.nd_this_port_only', function() {
      event.preventDefault(); // link is real so prevent page submit

      var port = $(this).text();
      port = $.trim(port);
      sweep.val(port);

      $('.field_clear_icon').show();
      $('#ports_form').trigger('submit');
    });
  });
