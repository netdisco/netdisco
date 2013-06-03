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

// for growl-like functionality, check for notifications periodically
(function worker() {
  $.ajax({
    url: uri_base + '/ajax/userlog'
    ,success: function(data) {
      for (var i = 0; i < data['error'].length; i++) {
        toastr.error(data['error'][i], 'Failed Change Request');
      }
      for (var i = 0; i < data['done'].length; i++) {
        toastr.success(data['done'][i], 'Successful Change Request');
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
