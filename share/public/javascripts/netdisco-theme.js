// Loaded as a blocking script at the top of <head>, so the color mode is set
// before first paint. A file rather than inline, so a strict CSP allows it.
(function () {
  'use strict';

  const root = document.documentElement;
  const darkQuery = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;

  /**
   * Where a theme choice can come from, highest priority first. Each returns a
   * theme name, or undefined to defer to the next. A per-user choice goes in
   * ahead of the server's configured default.
   * @type {Array<function(): (string|undefined)>}
   */
  const sources = [() => root.dataset.ndThemeDefault];

  /**
   * Picks the first theme name any source offers.
   * @returns {string} a theme name, or '' for Bootstrap's light default
   */
  function preferred() {
    for (const source of sources) {
      const name = source();
      if (name) return name;
    }
    return '';
  }

  /**
   * Turns a theme name into the color mode Bootstrap reads. 'light' and
   * 'auto' are reserved: 'light' means the standard colors, and 'auto'
   * follows the browser's color-scheme preference, which normally mirrors
   * the operating system, between dark and the standard colors.
   * @param {string} name a theme name
   * @returns {string} the data-bs-theme value, or '' for none (the standard
   *   colors); any name other than 'light' and 'auto' passes through
   */
  function colorMode(name) {
    if (name === 'light') return '';
    if (name !== 'auto') return name;
    return darkQuery && darkQuery.matches ? 'dark' : '';
  }

  /**
   * Links the stylesheet a color mode needs when the page does not already
   * link it. The page links the configured default, and auto's sheet is dark.
   * @param {string} mode the data-bs-theme value about to be set
   * @returns {void}
   */
  function ensureSheet(mode) {
    const configured = root.dataset.ndThemeDefault === 'auto' ? 'dark' : root.dataset.ndThemeDefault;
    if (!mode || mode === configured) return;
    const escaped = typeof CSS !== 'undefined' && CSS.escape ? CSS.escape(mode) : mode;
    if (document.querySelector(`link[data-nd-theme-sheet="${escaped}"]`)) return;
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = root.dataset.ndThemeRoot + encodeURIComponent(mode) + '.css';
    link.dataset.ndThemeSheet = mode;
    document.head.appendChild(link);
  }

  /**
   * Applies the preferred theme: sets data-bs-theme, or removes it when the
   * mode is '' (the standard colors). Safe to call again whenever a source changes.
   * @returns {void}
   */
  function apply() {
    const mode = colorMode(preferred());
    ensureSheet(mode);
    // Stock light has rules keyed on :root:not([data-bs-theme]), so the
    // standard colors must be the absence of the attribute.
    if (mode) root.setAttribute('data-bs-theme', mode);
    else root.removeAttribute('data-bs-theme');
  }

  apply();
  if (darkQuery) darkQuery.addEventListener('change', apply);
  window.ndTheme = { sources, apply };
})();
