// user clicked or asked for port changes to be submitted via ajax
function port_control (e) {
  var td = $(e).closest('td');

  $.ajax({
    type: 'POST'
    ,url: uri_base + '/ajax/portcontrol'
    ,data: {
      device:  td.attr('data-for-device')
      ,port:   td.attr('data-for-port')
      ,field:  td.attr('data-field')
      ,action: td.attr('data-action')
      ,value:  td.text().trim()
    }
    ,success: function() {
      toastr.info('Submitted change request');

      // update all the screen furniture for port up/down control
      if ($.trim(td.attr('data-action')) == 'down') {
        td.prev('td').html('<span class="label">S</span>');
        $(e).toggleClass('icon-hand-down');
        $(e).toggleClass('icon-hand-up');
        $(e).data('tooltip').options.title = 'Click to Enable';
        td.attr('data-action', 'up');
      }
      else if ($.trim(td.attr('data-action')) == 'up') {
        td.prev('td').html('<span class="label"><i class="icon-refresh"></i></span>');
        $(e).toggleClass('icon-hand-up');
        $(e).toggleClass('icon-hand-down');
        $(e).data('tooltip').options.title = 'Click to Disable';
        td.attr('data-action', 'down');
      }
      else if ($.trim(td.attr('data-action')) == 'false') {
        $(e).next('span').text('');
        $(e).toggleClass('nd_power-on');
        $(e).data('tooltip').options.title = 'Click to Enable';
        td.attr('data-action', 'true');
      }
      else if ($.trim(td.attr('data-action')) == 'true') {
        $(e).toggleClass('nd_power-on');
        $(e).data('tooltip').options.title = 'Click to Disable';
        td.attr('data-action', 'false');
      }
    }
    ,error: function() {
      toastr.error('Failed to submit change request');
      document.execCommand('undo');
      $(e).blur();
    }
  });
}

// on load, establish global delegations for now and future
$(document).ready(function() {
  // for growl-like functionality, check for notifications periodically
  if (nd_port_control) {
    (function worker() {
      $.ajax({
        url: uri_base + '/ajax/userlog'
        ,success: function(data) {
          for (var i = 0; i < data['error'].length; i++) {
            toastr.error(data['error'][i], 'Failed Job:');
          }
          for (var i = 0; i < data['done'].length; i++) {
            toastr.success(data['done'][i], 'Successful Job:');
          }
          // Schedule next request when the current one's complete
          setTimeout(worker, 5000);
        }
        ,error: function() {
          // after one failure, don't try again
          toastr.warning('Unable to retrieve change request log')
        }
      });
    })();
  }

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

  var dirty = false;

  // activity for contenteditable control
  $('.tab-content').on('keydown', '[contenteditable=true]', function(event) {
    var esc = event.which == 27,
        nl  = event.which == 13;

    if (esc) {
      $(this).blur();
    }
    else if (nl) {
      event.preventDefault();
      port_control(this); // save
      dirty = false;
      $(this).blur();
    }
    else {
      dirty = true;
    }
  });

  // activity for contenteditable control
  $('.tab-content').on('blur', '[contenteditable=true]', function(event) {
    if (dirty) {
      document.execCommand('undo');
      dirty = false;
      $(this).blur();
    }
  });

});
