// to tell whether bootstrap's modal had Submit button pressed :(
var nd_save_ok = false;

// Tracks the action after a submitted change without touching data-action,
// which stays as the server rendered it.
function getAction(el) {
  return (el.ndAction !== undefined) ? el.ndAction : el.dataset.action;
}

// Resets a cell's editable text to the value the server rendered; a bare
// control cell carries no .nd_editable-cell-content and is left alone.
function resetCellContent(td) {
  var content = td.querySelector('.nd_editable-cell-content');
  if (content) content.textContent = td.dataset.default;
}

// event.target is only ever an Element for the events delegated in this
// file; the guard exists for the type checker, not because a non-Element
// target has been observed here.
/**
 * @param {Event} event
 * @param {string} selector
 * @returns {HTMLElement | null}
 */
function targetClosest(event, selector) {
  var target = event.target;
  if (!(target instanceof Element)) return null;
  var match = target.closest(selector);
  return match instanceof HTMLElement ? match : null;
}

/**
 * @param {ParentNode} root
 * @param {string} selector
 * @returns {HTMLElement | null}
 */
function queryElement(root, selector) {
  var match = root.querySelector(selector);
  return match instanceof HTMLElement ? match : null;
}

// user clicked or asked for port changes to be submitted via ajax
function port_control (e) {
  var td = e.closest('td');
  var reasonField = document.getElementById('nd_portlog-reason');
  var logField = document.getElementById('nd_portlog-log');
  if (!(reasonField instanceof HTMLSelectElement) || !(logField instanceof HTMLTextAreaElement)) return;
  var reason = reasonField.value,
      logmessage = logField.value;
  logField.value = '';

  if (nd_save_ok == false) {
    resetCellContent(td);
    td.blur();
    return;
  }
  nd_save_ok = false;

  var body = new URLSearchParams({
    device: td.dataset.forDevice
    ,port: td.dataset.forPort
    ,field: td.dataset.field
    ,action: (getAction(e) || getAction(td))
    ,value: td.textContent.trim()
    ,reason: reason
    ,log: logmessage
  });

  ndRequest.post(uri_base + '/ajax/portcontrol', body)
    .then(function (response) {
      return response.ok ? undefined : Promise.reject(new Error('port control request failed: ' + response.status));
    })
    .then(function() {
      ndToast.info('Submitted change request');

      // update all the screen furniture unless bouncing
      if (! e.classList.contains('fa-bullseye')) {
        if (String(getAction(td) == null ? '' : getAction(td)).trim() == 'down') {
          let prev = td.previousElementSibling;
          if (prev && prev.matches('td')) prev.innerHTML = '<i class="fas fa-xmark"></i>';
          e.classList.toggle('fa-hand-point-down');
          e.classList.toggle('fa-hand-point-up');
          let bullseye = e.parentElement.querySelector('.fa-bullseye');
          if (bullseye) bullseye.style.display = 'none';
          retitleTooltip(e, 'Enable Port');
          td.ndAction = 'up';
        }
        else if (String(getAction(td) == null ? '' : getAction(td)).trim() == 'up') {
          let prev = td.previousElementSibling;
          if (prev && prev.matches('td')) prev.innerHTML = '<i class="fas fa-arrows-rotate fa-spin"></i>';
          e.classList.toggle('fa-hand-point-up');
          e.classList.toggle('fa-hand-point-down');
          let bullseye = e.parentElement.querySelector('.fa-bullseye');
          if (bullseye) bullseye.style.display = '';
          retitleTooltip(e, 'Disable Port');
          td.ndAction = 'down';
        }
        else if (String(getAction(td) == null ? '' : getAction(td)).trim() == 'false') {
          var next = e.nextElementSibling;
          if (next && next.matches('span')) next.textContent = '';
          e.classList.toggle('nd_power-on');
          retitleTooltip(e, 'Enable Power');
          td.ndAction = 'true';
        }
        else if (String(getAction(td) == null ? '' : getAction(td)).trim() == 'true') {
          e.classList.toggle('nd_power-on');
          retitleTooltip(e, 'Disable Power');
          td.ndAction = 'false';
        }
      }
    })
    .catch(function() {
      ndToast.error('Failed to submit change request');
      resetCellContent(td);
      td.blur();
    });
}

// on load, establish global delegations for now and future
document.addEventListener('DOMContentLoaded', function() {
  // for growl-like functionality, check for notifications periodically
  if (nd_check_userlog) {
    (function worker() {
      ndRequest.getJSON(uri_base + '/ajax/userlog')
        .then(function(data) {
          for (var i = 0; i < data['error'].length; i++) {
            ndToast.error(data['error'][i], 'Failed Job:');
          }
          for (i = 0; i < data['done'].length; i++) {
            ndToast.success(data['done'][i], 'Successful Job:');
          }
          // Schedule next request when the current one's complete
          setTimeout(worker, 5000);
        })
        .catch(function() {
          // after failure, try less often
          setTimeout(worker, 60000);
        });
    })();
  }

  // Cast once: querySelectorAll's own return type carries only Element, and
  // that leaves every event registered below untyped for its listener too.
  var tabContents = /** @type {NodeListOf<HTMLElement>} */ (document.querySelectorAll('.tab-content'));

  // toggle visibility of port up/down and edit controls
  tabContents.forEach(function (root) {
    root.addEventListener('mouseenter', function (event) {
      var t = targetClosest(event, '.nd_editable-cell');
      // Native mouseenter/mouseleave fire separately at every ancestor whose
      // own boundary the pointer crossed, not just the delegate match, so a
      // move between the cell's own icon children must not retrigger this.
      if (!t || !root.contains(t) || event.target !== t) return;
      var hand = queryElement(t, ':scope > .nd_hand-icon');
      if (hand) hand.style.display = 'inline';
      if (document.activeElement !== t) {
        var edit = queryElement(t, ':scope > .nd_edit-icon'); // ports
        if (edit) edit.style.display = 'inline';
        var row = t.closest('tr');
        if (row) row.querySelectorAll('.nd_device-details-edit').forEach(function (el) { if (el instanceof HTMLElement) el.style.display = 'inline' }); // details
      }
    }, true);
  });
  tabContents.forEach(function (root) {
    root.addEventListener('mouseleave', function (event) {
      var t = targetClosest(event, '.nd_editable-cell');
      // Same crossed-boundary reasoning as the mouseenter handler above: a
      // move between the cell's own icon children must not hide them.
      if (!t || !root.contains(t) || event.target !== t) return;
      hideWithTooltip(t.querySelector(':scope > .nd_hand-icon'));
      if (document.activeElement !== t) {
        var edit = queryElement(t, ':scope > .nd_edit-icon'); // ports
        if (edit) edit.style.display = 'none';
        var row = t.closest('tr');
        if (row) row.querySelectorAll('.nd_device-details-edit').forEach(function (el) { if (el instanceof HTMLElement) el.style.display = 'none' }); // details
      }
    }, true);
  });
  tabContents.forEach(function (root) {
    root.addEventListener('focus', function (event) {
      var t = targetClosest(event, '[contenteditable=true]');
      if (!t || !root.contains(t)) return;
      var edit = queryElement(t, ':scope > .nd_edit-icon'); // ports
      if (edit) edit.style.display = 'none';
      var row = t.closest('tr');
      if (row) row.querySelectorAll('.nd_device-details-edit').forEach(function (el) { if (el instanceof HTMLElement) el.style.display = 'none' }); // details
    }, true);
  });

  // to tell whether bootstrap's modal had Submit button pressed :(
  const portsPane = document.getElementById('ports_pane');
  if (portsPane) {
    portsPane.addEventListener('click', function (event) {
      var t = targetClosest(event, '#nd_portlog-submit');
      if (!t || !portsPane.contains(t)) return;
      nd_save_ok = true;
    });

    // activity for port up/down control, power enable/disable control
    portsPane.addEventListener('click', function (event) {
      var t = targetClosest(event, '.fa-hand-point-up,.fa-hand-point-down,.nd_power-icon,.fa-bullseye');
      if (!t || !portsPane.contains(t)) return;
      var clicked = t; // create a closure
      var modal = document.getElementById('nd_portlog');
      if (!(modal instanceof HTMLElement)) return;
      modal.addEventListener('hidden.bs.modal', function() {
        port_control(clicked); // save
      }, { once: true });
      var reasonField = document.getElementById('nd_portlog-reason');
      if (reasonField instanceof HTMLSelectElement) {
        if (t.classList.contains('fa-hand-point-up')) {
          reasonField.value = 'resolved';
        }
        else {
          reasonField.value = 'other';
        }
      }
      bootstrap.Modal.getOrCreateInstance(modal).show();
    });
  }

  // has cell content changed?
  var dirty = false;

  // activity for contenteditable control
  tabContents.forEach(function (root) {
    root.addEventListener('keydown', function (event) {
      var cell = targetClosest(event, '[contenteditable=true]');
      if (!cell || !root.contains(cell)) return;
      var td = cell.closest('td'),
          esc = event.key === 'Escape',
          nl  = event.key === 'Enter';
      if (!td) return;

      if (esc) {
        cell.blur();
        if (cell instanceof HTMLInputElement) cell.value = "";
      }
      else if (nl) {
        event.preventDefault();

        if (td.dataset.field == 'c_pvid') {
          var modal = document.getElementById('nd_portlog');
          if (!(modal instanceof HTMLElement)) return;
          modal.addEventListener('hidden.bs.modal', function() {
            port_control(cell); // save
          }, { once: true });
          bootstrap.Modal.getOrCreateInstance(modal).show();
        }
        else if (td.dataset.field == 'nd_left-acl-rule-field') {
          if (!(cell instanceof HTMLInputElement)) return;
          if (cell.value.length == 0) { return }
          let input = document.createElement('input');
          input.className = 'nd_left-acl-rule-field';
          input.dataset.form = 'update';
          input.name = 'left_rule';
          input.type = 'hidden';
          input.value = Math.floor( Date.now() / 1000 ) + '.' + window.btoa(cell.value);
          td.appendChild(input);
          let row = cell.closest('tr');
          let button = row && row.querySelector('button.nd_adminbutton[name="update"]');
          if (button instanceof HTMLElement) button.click();
        }
        else if (td.dataset.field == 'nd_right-acl-rule-field') {
          if (!(cell instanceof HTMLInputElement)) return;
          if (cell.value.length == 0) { return }
          let input = document.createElement('input');
          input.className = 'nd_right-acl-rule-field';
          input.dataset.form = 'update';
          input.name = 'right_rule';
          input.type = 'hidden';
          input.value = Math.floor( Date.now() / 1000 ) + '.' + window.btoa(cell.value);
          td.appendChild(input);
          let row = cell.closest('tr');
          let button = row && row.querySelector('button.nd_adminbutton[name="update"]');
          if (button instanceof HTMLElement) button.click();
        }
        else {
          // no confirm for port descr change
          nd_save_ok = true;
          port_control(cell); // save
        }

        dirty = false;
        cell.blur();
      }
      else {
        dirty = true;
      }
    });
  });

  // activity for contenteditable control
  tabContents.forEach(function (root) {
    root.addEventListener('blur', function (event) {
      var t = targetClosest(event, '[contenteditable=true]');
      if (!t || !root.contains(t)) return;
      if (dirty) {
        document.execCommand('undo');
        dirty = false;
        t.blur();
      }
    }, true);
  });

});
