// Admin-only page glue, split out of netdisco.js so it is parsed only on
// admin pages. Registers with ndPages (declared in netdisco.js) so
// netdisco.js can drive it without knowing admin exists. It reads
// netdisco.js's uri_base, nd_active_tab, nd_active_target and activeForm
// globals, and calls its nd_submit helper.

// admin jobqueue: keep track of timers so we can kill them
var nd_timers = new Array();
var timermax;
var timercache;

/**
 * The admin page's entry in the ndPages registry declared in netdisco.js,
 * which documents the three members. The rest of this file is the admin
 * fragments' handlers, bound at load because their markup exists only on
 * admin pages.
 */
ndPages.admin = {
  // no admin sidebar form carries the colored-input styling
  // device_form_state applies, so there is nothing to collect here.
  formInputs: function () {
    return $();
  },

  innerView: function (tab) {
    // reload this table every 5 seconds
    if ((tab == 'jobqueue')
        && $('#nd_countdown-control-icon').hasClass('fa-play')) {

        $('#nd_countdown').text(timermax);

        // add new timers
        for (var i = timercache; i > 0; i--) {
          nd_timers.push(setTimeout(function() {
            $('#nd_countdown').text(timercache);
            timercache = timercache - 1;
          }, ((timermax * 1000) - (i * 1000)) ));
        }

        nd_timers.push(setTimeout(function() {
          // clear any running timers
          for (var j = 0; j < nd_timers.length; j++) {
              clearTimeout(nd_timers[j]);
          }

          // reset the timer cache
          timercache = timermax - 1;

          // reload the tab content in...
          nd_submit('#' + tab + '_form');
        }, (timermax * 1000)));
    }

    // activate typeahead on the queue filter boxes
    $('.nd_queue_ta').autocomplete({
      source: function (request, response)  {
        var name = $(this.element)[0].name;
        var query = $(this.element).serialize();
        return $.get( uri_base + '/ajax/data/queue/typeahead/' + name, query, function (data) {
          return response(data);
        });
      }
      ,delay: 150
      ,minLength: 0
    });

    // activate typeahead on access control list editors
    $('.nd_acl_host_searcher').autocomplete({
      source: function (request, response)  {
        var query = $('.nd_sidebar-form').serializeArray();
        query.push($(this.element).serializeArray()[0]);
        return $.get( uri_base + '/ajax/data/devices/typeahead', query, function (data) {
          return response(data);
        });
      }
      ,select: function( event, ui ) {
        if (event.which == 13) { return };
        event.preventDefault();
        $(this).val(ui.item.value);
        $(this).trigger(jQuery.Event('keydown', { which: 13 }));
      }
      ,delay: 150
      ,minLength: 0
    });

    // activate typeahead on the topo boxes
    $('.nd_topo_dev').autocomplete({
      source: uri_base + '/ajax/data/deviceip/typeahead'
      ,delay: 150
      ,minLength: 0
    });

    // activate typeahead on the topo boxes
    $('.nd_topo_port.nd_topo_dev1').autocomplete({
      source: function (request, response)  {
        var query = $('.nd_topo_dev1').serialize();
        return $.get( uri_base + '/ajax/data/port/typeahead', query, function (data) {
          return response(data);
        });
      }
      ,delay: 150
      ,minLength: 0
    });

    // activate typeahead on the topo boxes
    $('.nd_topo_port.nd_topo_dev2').autocomplete({
      source: function (request, response)  {
        var query = $('.nd_topo_dev2').serialize();
        return $.get( uri_base + '/ajax/data/port/typeahead', query, function (data) {
          return response(data);
        });
      }
      ,delay: 150
      ,minLength: 0
    });

    $('.nd_jobqueue-extra').click(function(event) {
      event.preventDefault();
      var icon = $(this).children('i');
      $(icon).toggleClass('fa-plus');
      $(icon).toggleClass('fa-minus');
      var extra_id = $(this).data('extra');
      $('#' + extra_id).toggle();
    });
  },

  ready: function () {
    var tab = nd_active_tab;
    var target = nd_active_target;
    timermax = Number((activeForm && activeForm.dataset.ndJobqueueRefresh) || 5);
    timercache = timermax - 1;

    // get autocomplete field on input focus
    $('.nd_sidebar').on('focus', '.nd_queue_ta', function(e) {
      $(this).autocomplete('search', '%') });
    $('.nd_sidebar').on('click', '.nd_topo_dev_caret', function(e) {
      $(this).siblings('.nd_queue_ta').autocomplete('search', '%') });

    // get all devices on device input focus
    $('.nd_sidebar').on('focus', '.nd_topo_dev', function(e) {
      $(this).autocomplete('search', '%') });
    $('.nd_sidebar').on('click', '.nd_topo_dev_caret', function(e) {
      $(this).siblings('.nd_topo_dev').autocomplete('search', '%') });

    // get all devices on device input focus
    $(target).on('focus', '.nd_acl_host_searcher', function(e) {
      $(this).autocomplete('search', '%') });
    $(target).on('focus', '.nd_topo_dev', function(e) {
      $(this).autocomplete('search', '%') });
    $(target).on('click', '.nd_topo_dev_caret', function(e) {
      $(this).siblings('.nd_topo_dev').autocomplete('search', '%') });

    // get all ports on port input focus
    $(target).on('focus', '.nd_topo_port', function(e) {
      $(this).autocomplete('search') });
    $(target).on('click', '.nd_topo_port_caret', function(e) {
      $(this).siblings('.nd_topo_port').val('');
      $(this).siblings('.nd_topo_port').autocomplete('search');
    });

    // job control sidebar submit should reset timer
    // and update bookmark
    $('#' + tab + '_submit').click(function(event) {
      for (var i = 0; i < nd_timers.length; i++) {
          clearTimeout(nd_timers[i]);
      }
      // reset the timer cache
      timercache = timermax - 1;

      // bookmark
      var querystr = $('#' + tab + '_form').serialize();
      $('#nd_jobqueue-bookmark').attr('href',uri_base + '/admin/' + tab + '?' + querystr);
    });

    // job control refresh icon should reload the page
    $('#nd_countdown-refresh').click(function(event) {
      event.preventDefault();
      for (var i = 0; i < nd_timers.length; i++) {
          clearTimeout(nd_timers[i]);
      }
      // reset the timer cache
      timercache = timermax - 1;
      // and reload content
      nd_submit('#' + tab + '_form');
    });

    // job control pause/play icon switcheroo
    $('#nd_countdown-control').click(function(event) {
      event.preventDefault();
      var icon = $('#nd_countdown-control-icon');
      icon.toggleClass('fa-pause fa-play text-danger text-success');

      if (icon.hasClass('fa-pause')) {
        for (var i = 0; i < nd_timers.length; i++) {
            clearTimeout(nd_timers[i]);
        }
        $('#nd_countdown').text('0');
      }
      else {
        nd_submit('#' + tab + '_form');
      }
    });

    // activity for admin task tables
    // dynamically bind to all forms in the table
    $('.content').on('click', '.nd_adminbutton', function(event) {
      // stop form from submitting normally
      event.preventDefault();

      // clear any running timers
      for (var i = 0; i < nd_timers.length; i++) {
          clearTimeout(nd_timers[i]);
      }

      // what purpose - add/update/del
      var mode = $(this).attr('name');

      // admin task name with special case(s)
      var task = tab + '/';
      if (tab == 'duplicatedevices') {
        task = '';
      }

      // submit the query and put results into the tab pane
      $.ajax({
        type: 'POST'
        ,async: true
        ,dataType: 'html'
        ,url: uri_base + '/ajax/control/admin/' + task + mode
        ,data: $(this).closest('tr').find('input[data-form="' + mode + '"],select[data-form="' + mode + '"]').serializeArray()
        ,beforeSend: function() {
          if (mode == 'add' || mode == 'delete') {
            $(target).html(
              '<div class="col-md-2 alert">Request submitted...</div>'
            );
          }
        }
        ,success: function(data) {
          if (mode == 'add') {
            toastr.success('Added record');
            nd_submit('#' + tab + '_form');
          }
          else if (mode == 'delete') {
            toastr.success('Deleted record');
            nd_submit('#' + tab + '_form');
          }
          else {
            toastr.success('Updated record');
          }
          nd_submit('#' + tab + '_form');
        }
        // TODO: fix sanity_ok in Netdisco Web
        ,error: function() {
          if (mode == 'add') {
            toastr.error('Failed to add record');
            nd_submit('#' + tab + '_form');
          }
          else if (mode == 'delete') {
            toastr.error('Failed to delete record');
            nd_submit('#' + tab + '_form');
          }
          else {
            toastr.error('Failed to update record');
          }
        }
      });
    });

    // show the event log output on hover, delegated from the pane so that rows
    // the table redraws are covered without re-initialising. the rows carry
    // their log in data-content, which the backend writes and bootstrap does
    // not read, so the content comes from a callback rather than renaming the
    // attribute. html is left off, so the log is inserted as text.
    new bootstrap.Popover(target, {
      selector: '.nd_jobqueueitem',
      content: function() { return this.getAttribute('data-content'); },
      trigger: 'hover',
      placement: 'bottom',
      delay: { show: 100, hide: 0 },
      customClass: 'nd_jobqueue-popover'
    });
  }
};

// admin ACL editor: the bin beside a rule removes the rule's label and its
// input, then presses the row's update button. The button is found first
// because the click removes the label the search would start from.
document.addEventListener('click', function (event) {
  var bin = event.target.closest('.nd_delete-me');
  if (!bin) return;
  var row = bin.closest('tr');
  var button = row && row.querySelector('button.nd_adminbutton[name="update"]');
  var label = bin.closest('span.nd_left-acl-rule-label, span.nd_right-acl-rule-label');
  if (!label) return;
  var field = label.nextElementSibling;
  if (field && field.matches('input.nd_left-acl-rule-field, input.nd_right-acl-rule-field')) field.remove();
  label.remove();
  if (button) button.click();
});

// admin pseudo devices: the layer-3 badge toggles the hidden layers field
// between "router" and "nothing".
document.addEventListener('click', function (event) {
  var link = event.target.closest('.nd_layer-three-link');
  if (!link) return;
  var badge = link.querySelector('span');
  var layers = link.parentElement.querySelector('input');
  if (!badge || !layers) return;
  badge.classList.toggle('text-bg-success');
  layers.setAttribute('value', badge.classList.contains('text-bg-success') ? '00000100' : '00000000');
});

// admin users: the auth method select shows either the password field or
// the token controls, per row. Guarded per element because the add row
// carries no password field under no_auth and no token hint or button,
// which a plain field lookup would otherwise throw on.
function nd_token_fields(select) {
  var row = select.closest('tr');
  var pw = row.querySelector('.nd_pw_field');
  var cell = pw && pw.closest('td');
  var hint = row.querySelector('.nd_token_hint');
  var ips = row.querySelector('.nd_allowed_ips_field');
  var btn = row.querySelector('.nd_tokenbutton');
  var token = (select.value === 'permanent_token');
  if (pw) { pw.hidden = token; pw.disabled = token; if (token) pw.value = ''; else pw.placeholder = ''; }
  if (cell) { cell.classList.toggle('nd_center-middle-cell', token); cell.classList.toggle('nd_center-cell', !token) }
  if (hint) hint.hidden = !token;
  if (btn) btn.hidden = !token;
  if (ips) { ips.disabled = !token; if (!token) ips.value = '' }
}
document.addEventListener('change', function (event) {
  if (event.target.matches('.nd_auth_method')) nd_token_fields(event.target);
});
// Registered here at top level rather than inside a ready callback, so
// this attaches ahead of netdisco.js's own htmx:afterSwap listener, which
// builds the DataTable and runs from $(document).ready. DataTables detaches
// rows outside the current page from the DOM, and this sync must see every
// row while they are all still there.
document.body.addEventListener('htmx:afterSwap', function (evt) {
  evt.detail.target.querySelectorAll('.nd_auth_method').forEach(nd_token_fields);
});
document.addEventListener('click', function (event) {
  var copy = event.target.closest('#nd_token-copy');
  if (!copy) return;
  navigator.clipboard.writeText(document.getElementById('nd_token-value').value);
  copy.innerHTML = '<i class="fas fa-check"></i> Copied';
});

// admin users: the key icon requests a fresh permanent token for a
// token-only user. The route is declared with Dancer's ajax keyword, which
// matches only a request carrying X-Requested-With: XMLHttpRequest; $.get
// sent that automatically, fetch does not.
document.addEventListener('click', function (event) {
  var btn = event.target.closest('.nd_tokenbutton');
  if (!btn) return;
  var hint = btn.closest('td').querySelector('.nd_token-hint-value');
  var query = new URLSearchParams({ username: btn.dataset.username, permanent: 1 });
  fetch(uri_base + '/ajax/control/admin/users/token?' + query,
    { headers: { 'X-Requested-With': 'XMLHttpRequest' } })
    .then(function (response) { return response.ok ? response.text() : Promise.reject(new Error('token request failed: ' + response.status)) })
    .then(function (apiKey) {
      var key = apiKey.trim();
      if (key && typeof window.nd_show_api_token === 'function') {
        hint.textContent = '...' + key.slice(-8);
        window.nd_show_api_token(key);
      } else {
        toastr.error('Could not retrieve token');
      }
    })
    .catch(function () { toastr.error('Could not retrieve token') });
});

// Opens the token modal for a freshly issued API token
window.nd_show_api_token = function(apiKey) {
  document.getElementById('nd_token-value').value = apiKey;
  document.getElementById('nd_token-copy').innerHTML = '<i class="fas fa-copy"></i> Copy';
  // Name the form rather than building its id from task.tag. This fragment
  // is only ever rendered by the ajax route in Users.pm, which passes no task
  // in its stash, so task.tag was always empty here and the selector was
  // always '#_form', which matches nothing. The tag is 'users' either way:
  // this template is registered for that one admin task.
  document.getElementById('nd_token-reveal').addEventListener('hidden.bs.modal', function() {
    nd_submit('#users_form');
  }, { once: true });
  bootstrap.Modal.getOrCreateInstance(document.getElementById('nd_token-reveal')).show();
};
