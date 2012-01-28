    // fix green background on search checkboxes
    // https://github.com/twitter/bootstrap/issues/742
    syncCheckBox = function() {
      $(this).parents('.add-on').toggleClass('active', $(this).is(':checked'));
    };
    $('.add-on :checkbox').each(syncCheckBox).click(syncCheckBox);
