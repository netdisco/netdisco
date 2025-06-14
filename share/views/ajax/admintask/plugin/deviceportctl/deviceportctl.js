$(document).ready(function() {
    var tab = '[% task.tag | html_entity %]'
    var target = '#' + tab + '_pane';

    function setToPermit(port){
        var imgSrc = $(port).find("img")[0];
        imgSrc.src = "../images/port_permit.png";
        imgSrc.classList.remove("deny");
        imgSrc.classList.add("permit");
    }

    function setToDeny(port){
        var imgSrc = $(port).find("img")[0];
        imgSrc.src = "../images/port_deny.png";
        imgSrc.classList.remove("permit");
        imgSrc.classList.add("deny");
    }

    function togglePort(block){
        var imgSrc = $(block).find("img")[0];
        if (imgSrc.classList.contains("deny")) {
            setToPermit(block);
        } else {
            setToDeny(block);
        }
    }

    $('.port').on("click", function(event){
        togglePort(this);
    });



    $('.nd_permit').on("click", function(event){
        const device = $(this).data('device');
        var ports = $('.switch-view-' + device);
        var all_ports = ports.find('.port');
        for (var i = 0; i < all_ports.length; i++) {
            var port = all_ports[i];
            setToPermit(port);
        }
    });
    $('.nd_deny').on("click", function(event){
        const device = $(this).data('device');
        var ports = $('.switch-view-' + device);
        var all_ports = ports.find('.port');
        for (var i = 0; i < all_ports.length; i++) {
            var port = all_ports[i];
            setToDeny(port);
        }
    });

    $('.nd_save_port').on("click", function(event){
        const device = $(this).data('device');
        const group = $(this).data('group');
        let result = {"device":  device, "group": group, "ports": {}};
        var ports = $('.switch-view-' + device);
        var all_ports = ports.find('.port');

        for (var i = 0; i < all_ports.length; i++) {
            var port = all_ports[i];
            if (!port.id || port.id === "empty"){
                continue;
            }
            var span = $(port).find("img")[0];
            result["ports"][port.id] = span.classList.contains('permit') ? true : false;
        }
        var res = {"data": JSON.stringify(result)};
        
        $.ajax({
            type: 'POST'
            ,async: true
            ,dataType: 'html'
            ,url: uri_base + '/ajax/control/admin/deviceportctl'
            ,data: res,
            success: function(data){
                toastr.success('Added record');
                $('#' + tab + '_form').trigger('submit');
            },
            failure: function(errMsg) {
                toastr.error('Failed to add record');
            }
        });
    }
    );
});