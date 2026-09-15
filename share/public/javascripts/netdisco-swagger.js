/**
 * Netdisco's configuration of the Swagger UI bundle.
 *
 * Kept outside share/public/swagger-ui so that replacing the vendored files
 * cannot revert it.
 */
(function () {
  'use strict';

  /** Where the definition lives when the page is given no usable candidate. */
  const DEFAULT_SPEC_URL = '../swagger.json';

  /**
   * Resolve a ?url= candidate to a path this page is willing to load.
   *
   * Swagger UI 4.1.3 and later ignore ?url= unless queryConfigEnabled is set,
   * and that switch also re-enables configUrl and every other query key, so the
   * parameter is read here rather than by the bundle. Netdisco never sends one,
   * but a bookmark or a third party can, and the bundle fetches whatever url it
   * is handed.
   *
   * @param {string|null|undefined} candidate the raw ?url= value
   * @param {string} [href] the page address to resolve against
   * @returns {string|null} a same-origin path, or null to use the default
   */
  function sameOriginSpecUrl(candidate, href) {
    if (!candidate) return null;

    const base = href || window.location.href;
    let resolved;
    try {
      resolved = new URL(candidate, base);
    } catch (e) {
      return null;
    }

    // For http and https the URL parser treats a backslash as a path separator,
    // so "/\evil.com/x.json" reads as relative to a string match but resolves to
    // another origin. Comparing origins is what catches it.
    if (resolved.origin !== new URL(base).origin) return null;

    // Same origin alone would accept any JSON an attacker can get served from
    // this host. A path-prefixed deployment still ends in /swagger.json.
    if (!resolved.pathname.endsWith('/swagger.json')) return null;

    // The path rather than resolved.href, so the topbar URL field stays short.
    return resolved.pathname + resolved.search;
  }

  /**
   * Build the options handed to SwaggerUIBundle.
   *
   * @param {string} specUrl the definition to load
   * @returns {object} the bundle options
   */
  function bundleOptions(specUrl) {
    return {
      url: specUrl,
      dom_id: '#swagger-ui',
      deepLinking: true,
      presets: [window.SwaggerUIBundle.presets.apis, window.SwaggerUIStandalonePreset],
      plugins: [window.SwaggerUIBundle.plugins.DownloadUrl],
      layout: 'StandaloneLayout',
      apisSorter: 'alpha',
      operationsSorter: 'alpha',
      docExpansion: 'none',
      // The validator badge is on by default and sends the definition URL to a
      // Swagger-hosted service on every page load, publishing an internal
      // hostname. It cannot be caught in local testing: the badge suppresses
      // itself when the URL contains localhost or 127.0.0.1.
      validatorUrl: null
    };
  }

  /** Read the address bar, check the candidate, and start the bundle. */
  function start() {
    const requested = new URLSearchParams(window.location.search).get('url');
    const specUrl = sameOriginSpecUrl(requested) || DEFAULT_SPEC_URL;
    window.ui = window.SwaggerUIBundle(bundleOptions(specUrl));
  }

  window.ndSwagger = { sameOriginSpecUrl, bundleOptions, start, DEFAULT_SPEC_URL };

  // Guarded so the file can be loaded without the bundle, which is how the
  // tests reach sameOriginSpecUrl.
  if (typeof window.SwaggerUIBundle === 'function') {
    window.addEventListener('load', start);
  }
})();
