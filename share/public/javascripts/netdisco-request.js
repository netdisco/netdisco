/**
 * Requests to netdisco's own ajax routes, and the two form serializations the
 * pages need. Kept in one place because Dancer's ajax keyword answers 404
 * without the XMLHttpRequest header, and a miss on an /ajax/ path stays cached
 * for the life of the worker that served it.
 */
(function () {
  'use strict';

  /**
   * Posts form-encoded fields to one of netdisco's ajax routes.
   * @param {string} url the route, already carrying uri_base
   * @param {URLSearchParams} body the fields to send
   * @returns {Promise<Response>} resolves for every status, including 4xx and 5xx
   */
  function post(url, body) {
    return fetch(url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        'X-Requested-With': 'XMLHttpRequest',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'
      },
      body: body
    });
  }

  /**
   * Normalizes a submitted value's line endings to CRLF, which is what a form
   * submission sends.
   * @param {string} value the raw field value
   * @returns {string} the value with CRLF line endings
   */
  function normalize(value) {
    return String(value).replace(/\r?\n/g, '\r\n');
  }

  /**
   * Collects the named fields inside an element. A field with no name, a
   * disabled field, and an unchecked box or radio each contribute nothing; a
   * multiple select contributes one pair per chosen option.
   * @param {Element} root the element to search inside
   * @param {string} selector which descendants to collect
   * @returns {URLSearchParams} the collected pairs, in document order
   */
  function fields(root, selector) {
    const out = new URLSearchParams();
    Array.prototype.forEach.call(root.querySelectorAll(selector), (el) => {
      if (!el.name || el.matches(':disabled')) return;
      if ((el.type === 'checkbox' || el.type === 'radio') && !el.checked) return;
      // A multiple select contributes one pair per chosen option. Its `value`
      // is only the first, so a sidebar filtering on several vendors would
      // send one and silently drop the rest.
      if (el.type === 'select-multiple') {
        Array.prototype.forEach.call(el.selectedOptions, (option) => {
          out.append(el.name, normalize(option.value));
        });
        return;
      }
      out.append(el.name, normalize(el.value));
    });
    return out;
  }

  /**
   * Serializes a form to a query string.
   * @param {Element} form the form
   * @returns {string} the query string, with no leading question mark
   */
  function query(form) {
    return fields(form, 'input, select, textarea').toString();
  }

  /**
   * Fetches from one of netdisco's ajax routes.
   * @param {string} url the route, already carrying uri_base
   * @returns {Promise<Response>} resolves for every status, including 4xx and 5xx
   */
  function get(url) {
    return fetch(url, {
      credentials: 'same-origin',
      headers: { 'X-Requested-With': 'XMLHttpRequest' }
    });
  }

  /**
   * Fetches and parses JSON: a failed response is an error rather than a body
   * to parse.
   * @param {string} url the route, already carrying uri_base
   * @returns {Promise<any>} the parsed body
   */
  function getJSON(url) {
    return get(url).then((res) => {
      if (!res.ok) throw new Error('request for ' + url + ' answered ' + res.status);
      return res.json();
    });
  }

  /**
   * @typedef {object} NdRequestWindowProps
   * @property {object} [ndRequest] the post, get, getJSON, fields and query functions above, exported for tests
   */
  /** @type {Window & NdRequestWindowProps} */
  const ndWindow = window;
  ndWindow.ndRequest = {
    post: post,
    get: get,
    getJSON: getJSON,
    fields: fields,
    query: query
  };
})();
