  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'device';

  // fields in the Device Search Options form (Device tab)
  var form_inputs = $("#ports_form .clearfix input").not('[type="checkbox"]')
      .add("#ports_form .clearfix select");

  function inner_view_processing(tab) {
    // LT wanted the page title to reflect what's on the page :)
    document.title = $('#nd_device_name').text()
      +' - '+ $('#'+ tab + '_link').text();

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

    $('.nd_editable_cell').mouseenter(function() {
      $(this).children('.nd_hand_icon').show();
      if (! $(this).is(':focus')) {
        $(this).children('.nd_edit_icon').show(); // ports
        $(this).siblings('td').find('.nd_device_details_edit').show(); // details
      }
    });

    $('.nd_editable_cell').mouseleave(function() {
      $(this).children('.nd_hand_icon').hide();
      if (! $(this).is(':focus')) {
        $(this).children('.nd_edit_icon').hide(); // ports
        $(this).siblings('td').find('.nd_device_details_edit').hide(); // details
      }
    });

    $('[contenteditable=true]').focus(function() {
        $(this).children('.nd_edit_icon').hide(); // ports
        $(this).siblings('td').find('.nd_device_details_edit').hide(); // details
    });

    // activity for port up/down control
    $('.icon-hand-up').click(function() {
      port_control(this); // save
    });
    $('.icon-hand-down').click(function() {
      port_control(this); // save
    });

    // activity for power enable/disable control
    $('.nd_power_icon').click(function() {
      port_control(this); // save
    });

    var dirty = false;

    // activity for contenteditable control
    $('[contenteditable=true]').keydown(function() {
      var esc = event.which == 27,
          nl  = event.which == 13;

      if (esc) {
        if (dirty) { document.execCommand('undo') }
        $(this).blur();
        dirty = false;

      }
      else if (nl) {
        $(this).blur();
        event.preventDefault();
        dirty = false;
        port_control(this); // save
      }
      else {
        dirty = true;
      }
    });

    // show or hide netmap help button
    if (tab == 'netmap') {
      $('#netmap_help_img').show();
    }
    else {
      $('#netmap_help_img').hide();
    }

    // activate tooltips and popovers
    $("[rel=tooltip]").tooltip({live: true});
    $("[rel=popover]").popover({live: true});
  }

  $(document).ready(function() {
    // sidebar form fields should change colour and have bin/copy icon
    form_inputs.each(function() {device_form_state($(this))});
    form_inputs.change(function() {device_form_state($(this))});

    // sidebar collapser events trigger change of up/down arrow
    $('.collapse').on('show', function() {
      $(this).siblings().find('.arrow-up-down')
        .toggleClass('icon-chevron-up icon-chevron-down');
    });

    $('.collapse').on('hide', function() {
      $(this).siblings().find('.arrow-up-down')
        .toggleClass('icon-chevron-up icon-chevron-down');
    });

    // handler for bin icon in port filter box
    var portfilter = $('#ports_form').find("input[name=f]");
    $('.field_clear_icon').click(function() {
      portfilter.val('');
      $('#ports_form').trigger('submit');
      device_form_state(portfilter); // will hide copy icons
    });

    // clickable device port names can simply resubmit AJAX rather than
    // fetch the whole page again.
    $('body').on('click', '.nd_this_port_only', function() {
      event.preventDefault(); // link is real so prevent page submit

      var port = $(this).text();
      port = $.trim(port);
      portfilter.val(port);

      $('.field_clear_icon').show();
      $('#ports_form').trigger('submit');
      device_form_state(portfilter); // will hide copy icons
    });
  });
