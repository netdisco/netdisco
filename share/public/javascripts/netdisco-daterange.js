// The date range control's arithmetic, with no DOM in it so it can be tested
// directly. Calendar arithmetic throughout: setDate and the (year, month, 0)
// idiom leave month rollover and daylight saving to the platform.
(function () {
  'use strict';

  /**
   * Zero-pads a number to two digits for use in a formatted date.
   * @param {number} n the number to pad
   * @returns {string} n as a two-digit string
   */
  const pad = (n) => String(n).padStart(2, '0');

  /**
   * Formats a date as YYYY-MM-DD in the viewer's own timezone.
   * @param {Date} date the date to format
   * @returns {string} the date as YYYY-MM-DD
   */
  const formatDate = (date) => `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;

  /**
   * Offsets a date by a number of calendar days, without mutating it.
   * @param {Date} date the date to offset
   * @param {number} count the number of days to add, negative to subtract
   * @returns {Date} a new date, count days from date
   */
  const addDays = (date, count) => {
    const copy = new Date(date);
    copy.setDate(copy.getDate() + count);
    return copy;
  };

  /**
   * The first day of the month offset from date's month.
   * @param {Date} date the date whose month is the reference point
   * @param {number} offset months to add to date's month, negative for an earlier month, 0 for date's own month
   * @returns {Date} the 1st of the resulting month
   */
  const monthStart = (date, offset) => new Date(date.getFullYear(), date.getMonth() + offset, 1);

  /**
   * The last day of the month offset from date's month.
   * @param {Date} date the date whose month is the reference point
   * @param {number} offset months to add to date's month, negative for an earlier month, 0 for date's own month
   * @returns {Date} the last day of the resulting month
   */
  const monthEnd = (date, offset) => new Date(date.getFullYear(), date.getMonth() + offset + 1, 0);

  const PRESETS = {
    today: (base) => ({ from: addDays(base, 0), to: addDays(base, 0) }),
    yesterday: (base) => ({ from: addDays(base, -1), to: addDays(base, -1) }),
    last7: (base) => ({ from: addDays(base, -6), to: base }),
    last30: (base) => ({ from: addDays(base, -29), to: base }),
    thismonth: (base) => ({ from: monthStart(base, 0), to: monthEnd(base, 0) }),
    lastmonth: (base) => ({ from: monthStart(base, -1), to: monthEnd(base, -1) })
  };

  /**
   * Resolves a preset name to a pair of dates.
   * @param {string} name one of today, yesterday, last7, last30, thismonth, lastmonth
   * @param {Date} [base] the day to reckon from, defaulting to today
   * @returns {{from: Date, to: Date}|null} the range, or null for a name with no arithmetic
   */
  const presetRange = (name, base) => (PRESETS[name] ? PRESETS[name](base || new Date()) : null);

  /**
   * Splits the wire format into its two dates.
   * @param {string} text a value like "1970-01-01 to 2026-09-07"
   * @returns {string[]} both dates, or an empty array
   */
  const parseRange = (text) => String(text || '').match(/\d{4}-\d{2}-\d{2}/g) || [];

  /**
   * @typedef {object} NdDateRangeWindowProps
   * @property {object} [ndDateRange] the presetRange, formatDate and parseRange functions above, exported for tests
   */
  /** @type {Window & NdDateRangeWindowProps} */
  const ndWindow = window;
  ndWindow.ndDateRange = { presetRange, formatDate, parseRange };

  /**
   * The control's containing element, which carries the epoch-range default
   * and holds the select, inputs and hidden field that belong together.
   * @param {Element} element the select or date input to find the container for
   * @returns {HTMLElement} the nearest .nd_daterange ancestor
   */
  const container = (element) => /** @type {HTMLElement} */ (element.closest('.nd_daterange'));

  /**
   * The two date inputs inside a control, in from-then-to order.
   * @param {HTMLSelectElement} select the preset select
   * @returns {HTMLInputElement[]} the start and end date inputs
   */
  const inputs = (select) =>
    /** @type {HTMLInputElement[]} */ ([...container(select).querySelectorAll('.nd_daterange-input')]);

  /**
   * The hidden field a control's select and inputs write the wire value into.
   * @param {HTMLSelectElement} select the preset select
   * @returns {HTMLInputElement} the hidden field
   */
  const hidden = (select) => /** @type {HTMLInputElement} */ (container(select).querySelector('input[type=hidden]'));

  /**
   * The date pair block a control shows or hides depending on its preset.
   * @param {HTMLSelectElement} select the preset select
   * @returns {HTMLElement} the .nd_daterange-pair element
   */
  const pairElement = (select) => /** @type {HTMLElement} */ (container(select).querySelector('.nd_daterange-pair'));

  /**
   * Writes the two date inputs and the hidden field the server reads, and
   * shows or hides the pair to match whether "All dates" is selected.
   * @param {HTMLSelectElement} select the preset select
   * @param {string} from the start date as YYYY-MM-DD, or "" for no range at all
   * @param {string} to the end date as YYYY-MM-DD, or ""
   * @returns {void}
   */
  const apply = (select, from, to) => {
    const [start, end] = inputs(select);
    start.value = from;
    end.value = to;
    hidden(select).value = from && to ? `${from} to ${to}` : '';
    pairElement(select).hidden = select.value === 'all';
  };

  /**
   * Reacts to a change of preset: fills the inputs from the arithmetic for a
   * named preset, copies the container's all-dates default verbatim for "all"
   * (which is empty on pages that apply no filter without both dates), or
   * simply reveals the pair, untouched, for "custom".
   * @param {HTMLSelectElement} select the preset select that changed
   * @returns {void}
   */
  const applyPreset = (select) => {
    if (select.value === 'all') {
      // A report needs the epoch range because its field is required; node
      // search sends nothing, because its filter applies only when both dates
      // are there and a range would drop rows with no timestamp.
      const span = container(select).dataset.ndDaterangeAll;
      const parsed = span ? parseRange(span) : [];
      // Anything short of a full range (missing, one date, malformed) must
      // clear both fields, not leave a lone date to write the literal string
      // "undefined" into the other.
      const [from, to] = parsed.length === 2 ? parsed : ['', ''];
      apply(select, from, to);
      return;
    }
    const range = presetRange(select.value);
    if (range) {
      apply(select, formatDate(range.from), formatDate(range.to));
      return;
    }
    pairElement(select).hidden = false;
  };

  document.addEventListener('change', (event) => {
    const target = /** @type {Element} */ (event.target);
    const select = /** @type {HTMLSelectElement|null} */ (target.closest('select[data-nd-daterange]'));
    if (select) {
      applyPreset(select);
      return;
    }

    const input = target.closest('.nd_daterange-input');
    if (!input) {
      return;
    }
    // Typing a date makes the range custom by definition, so the label must
    // stop claiming a preset it no longer describes.
    const own = /** @type {HTMLSelectElement} */ (container(input).querySelector('select[data-nd-daterange]'));
    own.value = 'custom';
    const [start, end] = inputs(own);
    apply(own, start.value, end.value);
  });
})();
