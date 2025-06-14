$(document).ready(function() {
  var tab = '[% task.tag | html_entity %]'
  var target = '#' + tab + '_pane';


  $('.content').on('click', '.show-form', function(event){
    // this auto-checks the checkbox for the device if it's in the role's device list
    event.preventDefault();
    let role = $(this).data('role');
    let roleInput = $("#hidden-role");

    roleInput.val(role);

    let displayedDevices = $("#search").find(".checkbox");
    const roleDevices = $("#list-" + role).find("p").map(function() {
      return $.trim($(this).text());
    }).get();

    displayedDevices.each(function() {
      this.checked = roleDevices.includes(this.name);
    });
  });

  $('.content').on('click', '#checkall', function(event){
    event.preventDefault();
    let displayedDevices = $("#search").find(".checkbox");
    displayedDevices.each(function() {
      this.checked = true;
    });
  });
  
  $('.content').on('click', '.nd_role_device', function(event) {
    event.preventDefault();

    const mode = $(this).attr('name');
    const dataTable = $("#search").dataTable();
    /* Modified by BS */
    const checkedDevices = dataTable.$(".checkbox:checked").map(function() {
      return this.name;
    }).get();
    const res = {
      "device-list": checkedDevices.join(","),
      "role": $("#hidden-role").val()
    };

    $.ajax({
      type: 'POST',
      async: true,
      dataType: 'html',
      url: uri_base + '/ajax/content/admin/roleperm',
      data: res,
      beforeSend: function() {
        $(target).html(
          '<div class="span2 alert">Applying changes...</div>'
        );
      },
      success: function() {
        setTimeout(() => {
          //window.location.reload();
          toastr.success('Updated record');
        }, 1000);

        $('#' + tab + '_form').trigger('submit');
      },
      error: function() {
          toastr.error('Failed to update record');
      }
    });
  });
});
