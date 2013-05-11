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
    document.title = $('#nd_device-name').text()
      +' - '+ $('#'+ tab + '_link').text();

    // used for contenteditable cells to find out whether the user has made
    // changes, and only reset when they submit or cancel the change
    var dirty = false;

    // show or hide netmap help button
    if (tab == 'netmap') {
      $('#nd_netmap-help').show();
    }
    else {
      $('#nd_netmap-help').hide();
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
      $(this).siblings().find('.nd_arrow-up-down-right')
        .toggleClass('icon-chevron-up icon-chevron-down');
    });

    $('.collapse').on('hide', function() {
      $(this).siblings().find('.nd_arrow-up-down-right')
        .toggleClass('icon-chevron-up icon-chevron-down');
    });

    // handler for bin icon in port filter box
    var portfilter = $('#ports_form').find("input[name=f]");
    $('.nd_field-clear-icon').click(function() {
      portfilter.val('');
      $('#ports_form').trigger('submit');
      device_form_state(portfilter); // will hide copy icons
    });

    // clickable device port names can simply resubmit AJAX rather than
    // fetch the whole page again.
    $('#ports_pane').on('click', '.nd_this-port-only', function() {
      event.preventDefault(); // link is real so prevent page submit

      var port = $(this).text();
      port = $.trim(port);
      portfilter.val(port);

      $('.nd_field-clear-icon').show();
      $('#ports_form').trigger('submit');
      device_form_state(portfilter); // will hide copy icons
    });

    // VLANs column list collapser trigger
    // it's a bit of a faff because we can't easily use Bootstrap's collapser
    $('#ports_pane').on('click', '.nd_collapse-vlans', function() {
        $(this).siblings('.nd_collapsing').toggle();
        if ($(this).find('.nd_arrow-up-down-left').hasClass('icon-chevron-up')) {
          $(this).html('<div class="nd_arrow-up-down-left icon-chevron-down icon-large"></div>Hide VLANs');
        }
        else {
          $(this).html('<div class="nd_arrow-up-down-left icon-chevron-up icon-large"></div>Show VLANs');
        }
    });

    // toggle visibility of port up/down and edit controls
    $('.tab-content').on('mouseenter', '.nd_editable-cell', function() {
      $(this).children('.nd_hand-icon').show();
      if (! $(this).is(':focus')) {
        $(this).children('.nd_edit-icon').show(); // ports
        $(this).siblings('td').find('.nd_device-details-edit').show(); // details
      }
    });
    $('.tab-content').on('mouseleave', '.nd_editable-cell', function() {
      $(this).children('.nd_hand-icon').hide();
      if (! $(this).is(':focus')) {
        $(this).children('.nd_edit-icon').hide(); // ports
        $(this).siblings('td').find('.nd_device-details-edit').hide(); // details
      }
    });
    $('.tab-content').on('focus', '[contenteditable=true]', function() {
        $(this).children('.nd_edit-icon').hide(); // ports
        $(this).siblings('td').find('.nd_device-details-edit').hide(); // details
    });

    // activity for port up/down control
    $('#ports_pane').on('click', '.icon-hand-up', function() {
      port_control(this); // save
    });
    $('#ports_pane').on('click', '.icon-hand-down', function() {
      port_control(this); // save
    });

    // activity for power enable/disable control
    $('#ports_pane').on('click', '.nd_power-icon', function() {
      port_control(this); // save
    });

    // activity for contenteditable control
    $('.tab-content').on('keydown', '[contenteditable=true]', function() {
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
