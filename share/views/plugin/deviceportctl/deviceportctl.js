$(document).ready(function() {

    function setToPermit(port, device){
        var imgSrc = $(port).find("img")[0];
        imgSrc.src = "../images/port_permit.svg";
        imgSrc.classList.remove("deny");
        imgSrc.classList.add("permit");
        var portList = $("#port-list-" +device).val();
        $("#port-list-" + device).val( portList.replace(port.id + ",", ""));


    }

    function setToDeny(port, device){
        var imgSrc = $(port).find("img")[0];
        imgSrc.src = "../images/port_deny.svg";
        imgSrc.classList.remove("permit");
        imgSrc.classList.add("deny");
        var portList = $("#port-list-" +device).val();
        $("#port-list-" + device).val(portList + port.id + ",");
    }

    function togglePort(block){
        var imgSrc = $(block).find("img")[0];
        // Get the device from  a parent div data-device attribute
        const device =  $(block).closest('.switch').data('device');
        if (imgSrc.classList.contains("deny")) {
            setToPermit(block, device);
        } else {
            setToDeny(block, device);
        }
    }

    $(".content").on("click", ".port", function(event){

        togglePort(this);
    });


    $(".content").on("click", '.nd_permit', function(event){
        const device = $(this).data('device');
        var ports = $('.switch-view-' + device);
        var all_ports = ports.find('.port');
        for (var i = 0; i < all_ports.length; i++) {
            var port = all_ports[i];
            setToPermit(port, device);
        }
    });
    $(".content").on("click", '.nd_deny', function(event){
        const device = $(this).data('device');
        var ports = $('.switch-view-' + device);
        var all_ports = ports.find('.port');
        for (var i = 0; i < all_ports.length; i++) {
            var port = all_ports[i];
            setToDeny(port, device);
        }
    });

    $(".content").on("click", '.nd_show-device', function(event){
        const shortname = $(this).data('shortname');
        var td = $(this).closest('td');
        $(this).addClass('hidden');
        $.ajax({
            url: uri_base + '/ajax/content/admin/deviceportctl/device',
            data: {"device": $(this).data('device'), "role": $(this).data('role')},
            method: 'POST',
            success: function(data) {
                // remove the button
                // find closest td and find within the list of buttons the nd_deny, nd_permit and save buttons and show them

                console.log(td);
                td.find('.nd_deny').removeClass('hidden').prop('disabled', false);
                td.find('.nd_permit').removeClass('hidden').prop('disabled', false);
                td.find('.nd_adminbutton').removeClass('hidden').prop('disabled', false);
                $("#device-physical-view-" +  shortname).html(data);
                $("#device-physical-view-" +  shortname).parent().css('display', 'block');
            }
        });
    });

});