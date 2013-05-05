  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'admin';

  // this is called by do_search to support local code
  // here, when tab changes need to strike/unstrike the navbar search
  function inner_view_processing(tab) {
    var target = '#pseudodevice_pane';

    // activity for add pseudo device
    // dynamically bind to all forms in the table
    $(target).on('submit', 'form', function() {
      // stop form from submitting normally
      event.preventDefault();

      // submit the query and put results into the tab pane
      $.ajax({
        type: 'POST'
        ,async: false
        ,dataType: 'html'
        ,url: uri_base + '/ajax/content/admin/pseudodevice/' + $(this).attr('name')
        ,data: $(this).serializeArray()
        ,beforeSend: function() {
          $(target).html(
            '<div class="span2 alert">Waiting for results...</div>'
          );
        }
        ,success: function(content) {
          $(target).html(content);
        }
        ,error: function() {
          $(target).html(
            '<div class="span5 alert alert-error">' +
            'Update failed! Please contact your site administrator.</div>'
          );
        }
      });
    });
  }

  // on load, check initial Device Search Options form state,
  // and on each change to the form fields
  $(document).ready(function() { });
