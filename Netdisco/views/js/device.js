  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'device';

  function inner_view_processing() {
    // VLANs column list collapser trigger
    // it's a bit of a faff because we can't easily use Bootstrap's collapser
    $('.nd_collapse_vlans').toggle(function() {
        $(this).siblings('.nd_collapsing').toggle();
        $(this).siblings('.cell-arrow-up-down')
          .toggleClass('icon-chevron-up icon-chevron-down');
        $(this).html('<div class="cell-arrow-up-down icon-chevron-down icon-large"></div>Hide VLANs');
      }, function() {
        $(this).siblings('.nd_collapsing').toggle();
        $(this).siblings('.cell-arrow-up-down')
          .toggleClass('icon-chevron-up icon-chevron-down');
        $(this).html('<div class="cell-arrow-up-down icon-chevron-up icon-large"></div>Show VLANs');
    });

    // toggle visibility of port up/down and edit controls
    $('.nd_editable_cell').hover(function() {
      $(this).children('.nd_hand_icon').toggle();
      $(this).children('.nd_edit_icon').toggle();
    });

    // toggle visibility of VLAN edit control when clicked
    $('[contenteditable=true]').focus(function() {
      $(this).find('.nd_thumb_icon').toggle();
    });
    $('[contenteditable=true]').blur(function() {
      $(this).find('.nd_thumb_icon').toggle();
      // can undo but CSS doesn't shift, so just do nothing for now.
    });

    // activity for port up/down control
    $('.icon-hand-up').click(function() {
      port_control(this); // save
    });
    $('.icon-hand-down').click(function() {
      port_control(this); // save
    });

    // activity for contenteditable control
    $('.nd_thumb_icon').click(function() {
      $(this).closest('[contenteditable=true]').blur();
      port_control(this); // save
    });

    // activity for contenteditable control
    $('[contenteditable=true]').keydown(function() {
      var esc = event.which == 27,
          nl  = event.which == 13;

      if (esc) {
        document.execCommand('undo');
        $(this).blur();
      }
      else if (nl) {
        $(this).blur();
        event.preventDefault();
        port_control(this); // save
      }
    });

    // activate tooltips
    $("[rel=tooltip]").tooltip({live: true});
  }

  $(document).ready(function() {
    // sidebar collapser events trigger change of up/down arrow
    $('.collapse').on('show', function() {
      $(this).siblings().find('.arrow-up-down')
        .toggleClass('icon-chevron-up icon-chevron-down');
    });

    $('.collapse').on('hide', function() {
      $(this).siblings().find('.arrow-up-down')
        .toggleClass('icon-chevron-up icon-chevron-down');
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
