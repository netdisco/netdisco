  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'device';

  // fields in the Device Search Options form (Device tab)
  var form_inputs = $("#ports_form .clearfix input").not('[type="checkbox"]')
      .add("#ports_form .clearfix select");

  // this is called by do_search to support local code
  // which might need to act on the newly inserted content
  // but which cannot use jQuery delegation via .on()
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

    var dirty = false;

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

  // on load, establish global delegations for now and future
  $(document).ready(function() {
    var tab = '[% tab.tag %]'
    var target = '#' + tab + '_pane';

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
    $(target).on('click', '.nd_this_port_only', function() {
      event.preventDefault(); // link is real so prevent page submit

      var port = $(this).text();
      port = $.trim(port);
      portfilter.val(port);

      $('.field_clear_icon').show();
      $('#ports_form').trigger('submit');
      device_form_state(portfilter); // will hide copy icons
    });

    // toggle visibility of port up/down and edit controls
    $(target).on('mouseenter', '.nd_editable_cell', function() {
      $(this).children('.nd_hand_icon').show();
      if (! $(this).is(':focus')) {
        $(this).children('.nd_edit_icon').show(); // ports
        $(this).siblings('td').find('.nd_device_details_edit').show(); // details
      }
    });
    $(target).on('mouseleave', '.nd_editable_cell', function() {
      $(this).children('.nd_hand_icon').hide();
      if (! $(this).is(':focus')) {
        $(this).children('.nd_edit_icon').hide(); // ports
        $(this).siblings('td').find('.nd_device_details_edit').hide(); // details
      }
    });
    $(target).on('focus', '[contenteditable=true]', function() {
        $(this).children('.nd_edit_icon').hide(); // ports
        $(this).siblings('td').find('.nd_device_details_edit').hide(); // details
    });

    // activity for port up/down control
    $(target).on('click', '.icon-hand-up', function() {
      port_control(this); // save
    });
    $(target).on('click', '.icon-hand-down', function() {
      port_control(this); // save
    });

    // activity for power enable/disable control
    $(target).on('click', '.nd_power_icon', function() {
      port_control(this); // save
    });

    // activity for contenteditable control
    $(target).on('keydown', '[contenteditable=true]', function() {
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
  });
