$(document).ready(function() {

  $('.content').on('click', '#nd_devrole', function(event){
    let displayedDevices = $("#search").find(".device-selection");
    displayedDevices.each(function() {
      this.checked = false;
      $(this).trigger('change');
    });
  });

  $('.content').on('click', '.portpem', function(event){
    // this auto-checks the checkbox for the device if it's in the role's device list
    event.preventDefault();
    let role = $(this).data('role');
    let roleInput = $("#hidden-role");

    roleInput.val(role);

    let displayedDevices = $("#search").find(".device-selection");
    const roleDevices = $("#list-" + role).find("p").map(function() {
      return $.trim($(this).text());
    }).get();

    displayedDevices.each(function() {
      const isInList = roleDevices.includes(this.name);
      this.checked = isInList;
      $('#devices-checked').val(
        $('#devices-checked').val() +
        (isInList ? $(this).data('inet') + ',' : '')
      );
    });
  });
  
  $('.content').on('click', '#checkall', function(event){
    let displayedDevices = $("#search").find(".device-selection");
    displayedDevices.each(function() {
      this.checked = true;
      $(this).trigger('change');
    });
  });

  $('.content').on('click', '#uncheckall', function(event){
    let displayedDevices = $("#search").find(".device-selection");
    displayedDevices.each(function() {
      this.checked = false;
      $(this).trigger('change');
    });
  });
  $('.content').on('change', '.device-selection', function(event) {
    let inet = $(this).data('inet');
    let devicesChecked = $('#devices-checked');

    if ($(this).prop('checked')) {
      devicesChecked.val(devicesChecked.val() + inet + ',');
    }
    else {
      devicesChecked.val(devicesChecked.val().replace(inet + ',', ''));
    }
  });
  
  $('.content').on('click', '.device-row', function(event) {
  
    let checkbox = $(this).find('.device-selection');
    if (event.target === checkbox[0]) {
      return;
    }
    checkbox.prop('checked', !checkbox.prop('checked'));
    checkbox.trigger('change');
  });

});