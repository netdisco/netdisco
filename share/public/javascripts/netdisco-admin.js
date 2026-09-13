// Admin-only page glue, split out of netdisco.js so it is parsed only on
// admin pages. Registers with ndPages (declared in netdisco.js) so
// netdisco.js can drive it without knowing admin exists. It reads
// netdisco.js's uri_base, nd_active_tab, nd_active_target and activeForm
// globals.

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
    return [];
  },

  innerView: function (tab) {
    // reload this table every 5 seconds
    var countdownIcon = document.getElementById('nd_countdown-control-icon');
    if ((tab == 'jobqueue')
        && countdownIcon && countdownIcon.classList.contains('fa-play')) {

        var countdownLabel = document.getElementById('nd_countdown');
        if (countdownLabel) countdownLabel.textContent = String(timermax);

        // add new timers
        for (var i = timercache; i > 0; i--) {
          nd_timers.push(setTimeout(function() {
            var label = document.getElementById('nd_countdown');
            if (label) label.textContent = String(timercache);
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
          htmx.trigger('#' + tab + '_form', 'submit');
        }, (timermax * 1000)));
    }

    // Cast once: querySelectorAll's own return type carries only Element,
    // and that leaves .dataset untyped for the closure below.
    var extraButtons = /** @type {NodeListOf<HTMLElement>} */ (document.querySelectorAll('.nd_jobqueue-extra'));
    extraButtons.forEach(function (button) {
      button.addEventListener('click', function(event) {
        event.preventDefault();
        var icon = button.querySelector(':scope > i');
        if (icon) {
          icon.classList.toggle('fa-plus');
          icon.classList.toggle('fa-minus');
        }
        var extraId = button.dataset.extra;
        if (extraId) {
          var extra = document.getElementById(extraId);
          if (extra) extra.classList.toggle('nd_collapse-pre-hidden');
        }
      });
    });
  },

  ready: function () {
    var tab = nd_active_tab;
    var target = nd_active_target;
    timermax = Number((activeForm && activeForm.dataset.ndJobqueueRefresh) || 5);
    timercache = timermax - 1;

    // job control sidebar submit should reset timer
    // and update bookmark
    var submitBtn = document.getElementById(tab + '_submit');
    if (submitBtn) submitBtn.addEventListener('click', function() {
      for (var i = 0; i < nd_timers.length; i++) {
          clearTimeout(nd_timers[i]);
      }
      // reset the timer cache
      timercache = timermax - 1;

      // bookmark
      var tabForm = document.getElementById(tab + '_form');
      var querystr = tabForm ? ndRequest.query(tabForm) : '';
      var bookmark = document.getElementById('nd_jobqueue-bookmark');
      if (bookmark) bookmark.setAttribute('href', uri_base + '/admin/' + tab + '?' + querystr);
    });

    // job control refresh icon should reload the page
    var refreshBtn = document.getElementById('nd_countdown-refresh');
    if (refreshBtn) refreshBtn.addEventListener('click', function(event) {
      event.preventDefault();
      for (var i = 0; i < nd_timers.length; i++) {
          clearTimeout(nd_timers[i]);
      }
      // reset the timer cache
      timercache = timermax - 1;
      // and reload content
      htmx.trigger('#' + tab + '_form', 'submit');
    });

    // job control pause/play icon switcheroo
    var controlBtn = document.getElementById('nd_countdown-control');
    if (controlBtn) controlBtn.addEventListener('click', function(event) {
      event.preventDefault();
      var icon = document.getElementById('nd_countdown-control-icon');
      if (!icon) return;
      icon.classList.toggle('fa-pause');
      icon.classList.toggle('fa-play');
      icon.classList.toggle('text-danger');
      icon.classList.toggle('text-success');

      if (icon.classList.contains('fa-pause')) {
        for (var i = 0; i < nd_timers.length; i++) {
            clearTimeout(nd_timers[i]);
        }
        var countdownLabel = document.getElementById('nd_countdown');
        if (countdownLabel) countdownLabel.textContent = '0';
      }
      else {
        htmx.trigger('#' + tab + '_form', 'submit');
      }
    });

    // activity for admin task tables
    // dynamically bind to all forms in the table
    // const so TypeScript keeps the null-narrowing inside the closure below
    const content = document.querySelector('.content');
    if (content) content.addEventListener('click', function(event) {
      var button = event.target instanceof Element ? event.target.closest('.nd_adminbutton') : null;
      if (!button || !content.contains(button)) return;

      // stop form from submitting normally
      event.preventDefault();

      // clear any running timers
      for (var i = 0; i < nd_timers.length; i++) {
          clearTimeout(nd_timers[i]);
      }

      // what purpose - add/update/del
      var mode = button.getAttribute('name');

      // admin task name with special case(s)
      var task = tab + '/';
      if (tab == 'duplicatedevices') {
        task = '';
      }

      var row = button.closest('tr');
      if (!row) return;

      // collected before the pane is wiped below, which detaches this row
      var body = ndRequest.fields(row, 'input[data-form="' + mode + '"],select[data-form="' + mode + '"]');

      if (mode == 'add' || mode == 'delete') {
        var targetEl = document.querySelector(target);
        if (targetEl) {
          targetEl.textContent = '';
          var alertDiv = document.createElement('div');
          alertDiv.className = 'col-md-2 alert';
          alertDiv.textContent = 'Request submitted...';
          targetEl.appendChild(alertDiv);
        }
      }

      // submit the query and put results into the tab pane
      ndRequest.post(uri_base + '/ajax/control/admin/' + task + mode, body)
        .then(function (res) {
          // TODO: fix sanity_ok in Netdisco Web
          if (!res.ok) {
            if (mode == 'add') {
              ndToast.error('Failed to add record');
              htmx.trigger('#' + tab + '_form', 'submit');
            }
            else if (mode == 'delete') {
              ndToast.error('Failed to delete record');
              htmx.trigger('#' + tab + '_form', 'submit');
            }
            else {
              ndToast.error('Failed to update record');
            }
            return;
          }
          if (mode == 'add') {
            ndToast.success('Added record');
          }
          else if (mode == 'delete') {
            ndToast.success('Deleted record');
          }
          else {
            ndToast.success('Updated record');
          }
          // one refresh for every mode; add and delete also trigger their
          // own, so both would race into the pane if the sidebar did not
          // cancel its in-flight request first, and the aborted one logs
          // to the console.
          htmx.trigger('#' + tab + '_form', 'submit');
        }, function () {
          if (mode == 'add') {
            ndToast.error('Failed to add record');
            htmx.trigger('#' + tab + '_form', 'submit');
          }
          else if (mode == 'delete') {
            ndToast.error('Failed to delete record');
            htmx.trigger('#' + tab + '_form', 'submit');
          }
          else {
            ndToast.error('Failed to update record');
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
  if (!(event.target instanceof Element)) return;
  var bin = event.target.closest('.nd_delete-me');
  if (!bin) return;
  var row = bin.closest('tr');
  var button = row && row.querySelector('button.nd_adminbutton[name="update"]');
  var label = bin.closest('span.nd_left-acl-rule-label, span.nd_right-acl-rule-label');
  if (!label) return;
  var field = label.nextElementSibling;
  if (field && field.matches('input.nd_left-acl-rule-field, input.nd_right-acl-rule-field')) field.remove();
  label.remove();
  if (button instanceof HTMLElement) button.click();
});

// admin pseudo devices: the layer-3 badge toggles the hidden layers field
// between "router" and "nothing".
document.addEventListener('click', function (event) {
  if (!(event.target instanceof Element)) return;
  var link = event.target.closest('.nd_layer-three-link');
  if (!link) return;
  var badge = link.querySelector('span');
  var layers = link.parentElement && link.parentElement.querySelector('input');
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
  if (!(event.target instanceof Element)) return;
  if (event.target.matches('.nd_auth_method')) nd_token_fields(event.target);
});
// Registered here at top level rather than inside a ready callback, so
// this attaches ahead of netdisco.js's own htmx:after:swap listener, which
// builds the DataTable and runs from a DOMContentLoaded listener. DataTables
// detaches rows outside the current page from the DOM, and this sync must
// see every row while they are all still there.
document.body.addEventListener('htmx:after:swap', function (evt) {
  if (!(evt instanceof CustomEvent)) return;
  // htmx dispatches this on the element that made the request, so the pane is
  // read from the context
  evt.detail.ctx.target.querySelectorAll('.nd_auth_method').forEach(nd_token_fields);
});
document.addEventListener('click', function (event) {
  if (!(event.target instanceof Element)) return;
  var copy = event.target.closest('#nd_token-copy');
  if (!copy) return;
  var tokenValue = document.getElementById('nd_token-value');
  if (tokenValue instanceof HTMLInputElement) navigator.clipboard.writeText(tokenValue.value);
  copy.innerHTML = '<i class="fas fa-check"></i> Copied';
});

// admin users: the key icon requests a fresh permanent token for a
// token-only user. The route is declared with Dancer's ajax keyword, which
// matches only a request carrying X-Requested-With: XMLHttpRequest, so the
// request goes through ndRequest.get rather than a bare fetch.
document.addEventListener('click', function (event) {
  if (!(event.target instanceof Element)) return;
  var btn = event.target.closest('.nd_tokenbutton');
  if (!(btn instanceof HTMLElement)) return;
  var cell = btn.closest('td');
  var hint = cell && cell.querySelector('.nd_token-hint-value');
  var query = new URLSearchParams({ username: btn.dataset.username || '', permanent: '1' });
  ndRequest.get(uri_base + '/ajax/control/admin/users/token?' + query)
    .then(function (response) { return response.ok ? response.text() : Promise.reject(new Error('token request failed: ' + response.status)) })
    .then(function (apiKey) {
      var key = apiKey.trim();
      if (key && typeof window.nd_show_api_token === 'function') {
        if (hint) hint.textContent = '...' + key.slice(-8);
        window.nd_show_api_token(key);
      } else {
        ndToast.error('Could not retrieve token');
      }
    }, function () { ndToast.error('Could not retrieve token') });
});

// Opens the token modal for a freshly issued API token
window.nd_show_api_token = function(apiKey) {
  var tokenValue = document.getElementById('nd_token-value');
  if (tokenValue instanceof HTMLInputElement) tokenValue.value = apiKey;
  var tokenCopy = document.getElementById('nd_token-copy');
  if (tokenCopy) tokenCopy.innerHTML = '<i class="fas fa-copy"></i> Copy';
  // Name the form rather than building its id from task.tag. This fragment
  // is only ever rendered by the ajax route in Users.pm, which passes no task
  // in its stash, so task.tag was always empty here and the selector was
  // always '#_form', which matches nothing. The tag is 'users' either way:
  // this template is registered for that one admin task.
  var tokenReveal = document.getElementById('nd_token-reveal');
  if (!tokenReveal) return;
  tokenReveal.addEventListener('hidden.bs.modal', function() {
    htmx.trigger('#users_form', 'submit');
  }, { once: true });
  bootstrap.Modal.getOrCreateInstance(tokenReveal).show();
};
