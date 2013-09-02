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

    // activate modals, tooltips and popovers
    $('.nd_modal').modal({show: false});
    $("[rel=tooltip]").tooltip({live: true});
    $("[rel=popover]").popover({live: true});
  }

  // on load, establish global delegations for now and future
  $(document).ready(function() {
    var tab = '[% tab.tag %]'
    var target = '#' + tab + '_pane';

    // sidebar form fields should change colour and have trash/copy icon
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

    // handler for trashcan icon in port filter box
    var portfilter = $('#ports_form').find("input[name=f]");
    $('.nd_field-clear-icon').click(function() {
      portfilter.val('');
      $('#ports_form').trigger('submit');
      device_form_state(portfilter); // will hide copy icons
    });

    // clickable device port names can simply resubmit AJAX rather than
    // fetch the whole page again.
    $('#ports_pane').on('click', '.nd_this-port-only', function(event) {
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

    // activity for admin tasks in device details
    $('#details_pane').on('click', '.nd_adminbutton', function(event) {
      // stop form from submitting normally
      event.preventDefault();

      // what purpose - discover/macsuck/arpnip
      var mode = $(this).attr('name');
      var tr = $(this).closest('tr');

      // submit the query
      $.ajax({
        type: 'POST'
        ,async: true
        ,dataType: 'html'
        ,url: uri_base + '/ajax/control/admin/' + mode
        ,data: tr.find('input[data-form="' + mode + '"],textarea[data-form="' + mode + '"]').serializeArray()
        ,success: function() {
          toastr.info('Requested '+ mode +' for device '+ tr.data('for-device'));
        }
        // skip any error reporting for now
        // TODO: fix sanity_ok in Netdisco Web
        ,error: function() {
          toastr.error('Failed to '+ mode +' for device '+ tr.data('for-device'));
        }
      });
    });

    // bootstrap modal mucks about with mouse actions on higher elements
    // so need to bury and raise it when needed
    $('#ports_pane').on('show', '.nd_modal', function () {
      $(this).toggleClass('nd_deep-horizon');
    });
    $('#ports_pane').on('hidden', '.nd_modal', function () {
      $(this).toggleClass('nd_deep-horizon');
    });

    // clear any values in the delete confirm dialog
    $('#details_pane').on('hidden', '.nd_modal', function () {
      $('#nd_devdel-log').val('');
      $('#nd_devdel-archive').attr('checked', false);
    });
  });
