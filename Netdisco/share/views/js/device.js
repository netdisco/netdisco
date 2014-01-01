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

    // activate modals, tooltips and popovers
    $('.nd_modal').modal({show: false});
    $("[rel=tooltip]").tooltip({live: true});
    $("[rel=popover]").popover({live: true});
  }

  // on load, establish global delegations for now and future
  $(document).ready(function() {
    var tab = '[% tab.tag %]'
    var target = '#' + tab + '_pane';
    var portfilter = $('#ports_form').find("input[name=f]");

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

    // if the user edits the filter box, revert to automagical search
    $('#ports_form').on('input', "input[name=f]", function() {
      $('#nd_ports-form-prefer-field').attr('value', '');
    });

    // handler for trashcan icon in port filter box
    $('.nd_field-clear-icon').click(function() {
      portfilter.val('');
      $('#ports_form').trigger('submit');
      device_form_state(portfilter); // will hide copy icons
    });

    // allow port filter to have a preference for port/name/vlan
    $('#ports_form').on('click', '.nd_device-port-submit-prefer', function() {
      event.preventDefault();
      $('#nd_ports-form-prefer-field').attr('value', $(this).data('prefer'));
      $(this).parents('form').submit();
    });

    // clickable device port names can simply resubmit AJAX rather than
    // fetch the whole page again.
    $('#ports_pane').on('click', '.nd_this-port-only', function(event) {
      event.preventDefault(); // link is real so prevent page submit

      var port = $(this).text();
      port = $.trim(port);
      portfilter.val(port);
      $('.nd_field-clear-icon').show();

      // make sure we're preferring a port filter
      $('#nd_ports-form-prefer-field').attr('value', 'port');

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
          if (mode != 'delete') {
            toastr.info('Requested '+ mode +' for device '+ tr.data('for-device'));
          }
          else {
            toastr.success('Deleted device '+ tr.data('for-device'));
          }
        }
        // skip any error reporting for now
        // TODO: fix sanity_ok in Netdisco Web
        ,error: function() {
          toastr.error('Failed to '+ mode +' device '+ tr.data('for-device'));
        }
      });
    });

    // clear any values in the delete confirm dialog
    $('#details_pane').on('hidden', '.nd_modal', function () {
      $('#nd_devdel-log').val('');
      $('#nd_devdel-archive').attr('checked', false);
    });
  });
