// Notifications for the result of an action, drawn with Bootstrap's own toast
// component so no notification library of its own is needed. A message may
// echo a server response verbatim, so every one is written with textContent
// and never innerHTML.
const ndToast = (function () {
  'use strict';

  const DELAY = 5000;

  const STYLE_CLASSES = {
    success: 'nd_toast-success',
    error: 'nd_toast-error',
    info: 'nd_toast-info'
  };

  /**
   * The element all toasts stack inside, created on first use and reused
   * after, so each call adds to what is showing rather than replacing it.
   * @returns {HTMLElement} the container, appended to document.body
   */
  function toastContainer() {
    const CONTAINER_CLASS = 'nd_toast-container';
    const found = /** @type {HTMLElement|null} */ (document.querySelector('.' + CONTAINER_CLASS));
    if (found) {
      return found;
    }
    const created = document.createElement('div');
    created.className = 'toast-container position-fixed top-0 end-0 p-3 ' + CONTAINER_CLASS;
    document.body.appendChild(created);
    return created;
  }

  /**
   * Builds the dismiss button a toast offers beside its text.
   * @returns {HTMLButtonElement} a Bootstrap close button wired to dismiss the toast
   */
  function closeButton() {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'btn-close btn-close-white me-2 m-auto';
    button.setAttribute('data-bs-dismiss', 'toast');
    button.setAttribute('aria-label', 'Close');
    return button;
  }

  /**
   * Builds the text half of a toast: an optional bold title above the message,
   * both written as plain text so nothing here can be markup.
   * @param {string} message the text to show, never treated as markup
   * @param {string} [title] an optional heading shown above the message
   * @returns {HTMLElement} the toast-body element
   */
  function toastBody(message, title) {
    const body = document.createElement('div');
    body.className = 'toast-body';
    if (title) {
      const heading = document.createElement('div');
      heading.className = 'fw-bold';
      heading.textContent = title;
      body.appendChild(heading);
    }
    const text = document.createElement('div');
    text.textContent = message;
    body.appendChild(text);
    return body;
  }

  /**
   * Builds and shows one toast, colored for the given kind, and removes it
   * from the container once Bootstrap finishes hiding it.
   * @param {string} styleClass the Bootstrap text-bg-* class naming its color
   * @param {string} message the text to show, never treated as markup
   * @param {string} [title] an optional heading shown above the message
   * @returns {void}
   */
  function show(styleClass, message, title) {
    const el = document.createElement('div');
    el.className = 'toast align-items-center border-0 ' + styleClass;
    el.setAttribute('role', 'alert');
    el.setAttribute('aria-live', 'assertive');
    el.setAttribute('aria-atomic', 'true');

    const row = document.createElement('div');
    row.className = 'd-flex';
    row.appendChild(toastBody(message, title));
    row.appendChild(closeButton());
    el.appendChild(row);

    toastContainer().appendChild(el);
    el.addEventListener('hidden.bs.toast', function () {
      el.remove();
    });

    const toast = new bootstrap.Toast(el, { delay: DELAY });
    // The whole notification dismisses, which is what the pointer cursor over
    // it offers. The close button is left to the library, so that a keyboard
    // reaches one too.
    el.addEventListener('click', function (event) {
      if (!(/** @type {Element} */ (event.target)).closest('.btn-close')) {
        toast.hide();
      }
    });
    toast.show();
  }

  /**
   * Shows a toast styled as a success.
   * @param {string} message the text to show, never treated as markup
   * @param {string} [title] an optional heading shown above the message
   * @returns {void}
   */
  function success(message, title) {
    show(STYLE_CLASSES.success, message, title);
  }

  /**
   * Shows a toast styled as an error.
   * @param {string} message the text to show, never treated as markup
   * @param {string} [title] an optional heading shown above the message
   * @returns {void}
   */
  function error(message, title) {
    show(STYLE_CLASSES.error, message, title);
  }

  /**
   * Shows a toast styled as informational.
   * @param {string} message the text to show, never treated as markup
   * @param {string} [title] an optional heading shown above the message
   * @returns {void}
   */
  function info(message, title) {
    show(STYLE_CLASSES.info, message, title);
  }

  return {
    success: success,
    error: error,
    info: info
  };
})();
