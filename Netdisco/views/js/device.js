  function inner_view_processing() {
    // enable collapser on any large vlan lists
    $('.nd_collapse_vlans').collapser({
      target: 'next',
      effect: 'slide',
      changeText: true,
      expandHtml: '<div class="cell-arrow-up"></div><div class="nd_collapser">Show VLANs</div>',
      collapseHtml: '<div class="cell-arrow-down"></div><div class="nd_collapser">Hide VLANs</div>',
    });
  }

  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'device';

  $(document).ready(function() {
    $('#nd_collapse_columns').collapser({
      target: 'next',
      effect: 'slide',
      changeText: true,
      expandHtml: '<label class="nd_collapser">Display Columns<div class="arrow-up"></div></label>',
      collapseHtml: '<label class="nd_collapser">Display Columns<div class="arrow-down"></div></label>',
    });

    $('#nd_collapse_portprop').collapser({
      target: 'next',
      effect: 'slide',
      changeText: true,
      expandHtml: '<label class="nd_collapser">Port Properties<div class="arrow-up"></div></label>',
      collapseHtml: '<label class="nd_collapser">Port Properties<div class="arrow-down"></div></label>',
    });

    $('#nd_collapse_nodeprop').collapser({
      target: 'next',
      effect: 'slide',
      changeText: true,
      expandHtml: '<label class="nd_collapser">Node Properties<div class="arrow-up"></div></label>',
      collapseHtml: '<label class="nd_collapser">Node Properties<div class="arrow-down"></div></label>',
    });

    $('#nd_collapse_legend').collapser({
      target: 'next',
      effect: 'slide',
      changeText: true,
      expandHtml: '<label class="nd_collapser">Legend<div class="arrow-up"></div></label>',
      collapseHtml: '<label class="nd_collapser">Legend<div class="arrow-down"></div></label>',
    });

    // show or hide sweeping brush icon when field has content
    var sweep = $('#ports_form').find("input[name=q]");

    if (sweep.val() === "") {
      $('.field_clear_icon').hide();
    } else {
      $('.field_clear_icon').show();
    }

    sweep.change(function() {
      if ($(this).val() === "") {
        $('.field_clear_icon').hide();
      } else {
        $('.field_clear_icon').show();
      }
    });

    // handler for sweeping brush icon in port filter box
    $('.field_clear_icon').click(function() {
      sweep.val('');
      $('.field_clear_icon').hide();
      $('#ports_form').trigger('submit');
    });

    // everything starts hidden and then we show defaults
    $('#nd_collapse_legend').click();
  });
