// user clicked or asked for port changes to be submitted via ajax
function port_control (e) {
  var td = $(e).closest('.nd_editable_cell');

  $.ajax({
    type: 'POST'
    ,url: uri_base + '/ajax/portcontrol'
    ,data: {
      device:  td.data('for-device')
      ,port:   td.data('for-port')
      ,field:  td.data('field')
      ,action: td.data('action')
      ,value:  td.text().trim()
    }
    ,success: function() {
      toastr.info('Submitted change request');
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
      // console.log(data);

      if (data['error'] == 1 ) {
        toastr.error('1 recent failed change request');
      }
      else if (data['error'] > 1) {
        toastr.error(data['error'] + ' recent failed change requests');
      }

      if (data['done'] == 1 ) {
        toastr.success('1 recent successful change request');
      }
      else if (data['done'] > 1) {
        toastr.success(data['done'] + ' recent successful change requests');
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
