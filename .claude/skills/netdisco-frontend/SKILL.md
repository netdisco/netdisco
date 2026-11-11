---
name: netdisco-frontend
description: Use when changing or reviewing Netdisco's web frontend, meaning templates under share/views, scripts under share/public/javascripts, web plugins under lib/App/Netdisco/Web, or the DataTables a page builds, including tab, report and Ports tab work.
---

# Working on the Netdisco web frontend

The frontend was rebuilt in 2026: Bootstrap 5, htmx 4, DataTables 3 and no
jQuery. Older guides, forum answers and model training data describe the
jQuery frontend; none of it applies. The tests under `xt/js/` encode the
rules below, and each file's header comment says why its rule exists and
what it covers. Read the header of any test your change touches before
changing the test.

This skill states rules and names the file that owns the details. Where
they seem to disagree, the code is right; say so in the PR.

## Vendored libraries

- The libraries are files under `share/public/`; nothing builds or
  installs them. `package.json` lists each with its version so scanners
  can see what ships.
- **Replacing one** is one commit (model: #1753):
  1. Copy in the release's distributed files unmodified, the same files
     as before. Swagger UI is a subset of `swagger-ui-dist`: keep the
     files already in `share/public/swagger-ui/`.
  2. Update its version in `package.json`.
  3. Update `xt/33-vendored-manifest.t`. A file that states its version is
     checked from that; for one pinned by checksum, set `sha256` and
     `pinned_for` to the new version.
  4. Add `* #NNNN upgrade the vendored <library> from <old> to <new>` to
     `Changes`.
  5. Run `prove -Ilib xt/33-vendored-manifest.t`, the `xt/js` tests, and
     open the pages that use the library in a browser.
- A pull request that changes `package.json` alone fails `xt/33` on
  purpose: the declared version must describe the shipped bytes.
- **retire.js** (`.github/workflows/retirejs.yml`) fails on a vendored
  library with a known advisory. Fix it by vendoring a fixed release.
  Only when none exists and the advisory does not apply to how Netdisco
  uses the library, waive that version in `.retireignore.json` at the
  repository root with the reason (model: #1786), and delete the waiver
  when a fixed release is vendored.

## How a page loads

- A page (`share/views/device.tt`, `search.tt`, `report.tt`,
  `admintask.tt`) is a layout plus one sidebar form per tab. Each form
  loads its tab's `/ajax/content/...` route into its pane with htmx; read
  one of those templates for the attributes.
- **Every request to an `/ajax/` route sends `X-Requested-With:
  XMLHttpRequest`.** Dancer's `ajax` keyword answers 404 without it, and
  htmx 4 does not send it on its own. In markup use
  `hx-headers='{"X-Requested-With": "XMLHttpRequest"}'`; in script use the
  helpers in `netdisco-request.js`.
- **A report page loads its content by submitting its sidebar form,** so a
  query parameter on `/report/<tag>` reaches the content route only if the
  sidebar has a field of that name. To link into a report filtered by
  something, give its sidebar that field and select it from the parameter
  in a `before_template` hook.
- **htmx owns browser history.** Routes answer pane requests with
  `HX-Push-Url` or `HX-Replace-Url`; do not call `history.pushState`
  yourself.
- **Initialize after a swap, not on page load.** A pane arrives by htmx swap
  long after `DOMContentLoaded`. Hook `htmx:after:swap`, or register with
  `ndPages` and give your page an `innerView(tab)`, which runs after
  every pane swap; `ready()` runs once, on page load.
- **htmx binds triggers once, when it processes a node.** Rows that
  DataTables draws later have no htmx listeners, and a `once` trigger is
  spent before the request, so a failed fetch leaves the element inert.
  For an element inside a table, give it `hx-trigger="none"` and have a
  delegated listener call `htmx.ajax(verb, url, {source: elt})`, as
  `netdisco-deferred-nodes.js` does.
- **Pane settling:** whatever adds `nd_pane-settling` must be gated on the
  same condition as whatever removes it, or the pane stays hidden
  (`xt/js/pane-settling.test.js`).

## Where JavaScript goes

- **All JavaScript is static, in `share/public/javascripts/`.** A template
  fragment carries no `<script>` except a JSON data block
  (`<script type="application/json" id="...">`), and Template Toolkit
  generates no code. This keeps every script inside CodeQL's analysis and
  inside the `xt/js` tests.
- **No jQuery**, in any shipped script or the layout. Use the DOM API and
  Bootstrap 5's own JavaScript.
- **Page scripts register with `ndPages`** (declared in `netdisco.js`), so
  `netdisco.js` does not need to know which pages exist.
- **Authored functions carry JSDoc** with a description, parameters and
  return value, as in `netdisco-request.js`.

## Bootstrap components and events

- **Tooltips:** macOS Chrome fires no `mouseleave` when an element is
  hidden under a pointer that has not moved, so its tooltip is stranded.
  Linux browsers do not show this, so CI cannot either. Hide an element
  that may be showing a tooltip only through `hideWithTooltip()` in
  `netdisco.js`.
- **Popovers:** before a swap, call `hide()`, never `dispose()`, which
  throws on a tip caught mid-hide.
- **Bootstrap fires events only on transitions.** A component rendered
  open fires no `show` event, so initialize from its initial state as well
  as on its events.
- **Delegated listeners:** bind once on an element that outlives the swap,
  not on each element, because panes are swapped out. In the handler,
  `closest()` returns null for an element outside the container you
  expect; handle that case.
- **High-frequency events:** save or post when a drag or gesture settles,
  not on every `mousemove`.
- **Visibility:** a closed `<details>` hides its contents without
  `display: none`, so `offsetParent` still reports an element. Use
  `element.checkVisibility()`.

## Themes and styling

- **Bootstrap first.** Use Bootstrap 5.3's classes, utilities and
  components before writing CSS; add a rule to
  `share/public/css/netdisco.css` only when no Bootstrap class does the
  job. Colors come from Bootstrap's CSS variables (`var(--bs-...)`),
  never a literal color in a template, script or rule. Tests catch a
  literal only in some stylesheets, so check templates and scripts
  yourself.
- **Netdisco's own colors are `--nd-*` tokens**, defined in `:root` in
  `netdisco.css` and mapped onto Bootstrap's variables so they follow the
  color mode. A new colored element gets a token there.
- **Themes are Bootstrap color modes,** chosen by `web_theme`. A theme
  file sets Bootstrap's variables and the `--nd-*` tokens under
  `[data-bs-theme="<name>"]`. To write one, follow the header of
  `share/public/css/themes/classic.css`.
- **Theme tests:** `xt/117`, `xt/121` and `xt/122` check themes and
  tokens; their headers say what each covers. When you add a token, set
  it in `dark.css` too if Bootstrap's dark variables cannot express it.
- A canvas cannot see stylesheets: the network map's colors reach it only
  through the `--nd-netmap-*` tokens its script reads.
- Check new UI in light and dark.

## Tables

- **Every DataTable is built by `netdisco-tables.js`** from a
  `data-nd-table` attribute holding a DataTables options object. Renderers
  and callbacks are named in that file's registry and referenced by name
  from the JSON, never written as an inline closure in a template. The
  header comment in that file is the contract for the attribute and its
  siblings.
- **Use a renderer that exists before adding one.** The registry covers
  most cells, and each renderer's JSDoc lists its arguments. `deviceLink`
  and `subnetLink` draw a link even for an empty value (to `q=null`), so
  use them only on columns that are never empty, or use
  `searchDeviceLink` with `notSet`. `reportLink` sends an array key
  comma-joined, so the receiving route must split on commas. Add a
  renderer only for a cell no combination of existing ones can draw, with
  a test in `xt/js/tables-registry.test.js`.
- **One value or one link per cell.** When a cell would need several links,
  or a sentence with links inside it, change what a row is (one row per
  device, VRF or port) rather than build a composite cell. Sorting and
  searching then work per value.
- **Labels and URLs:** label a device by its DNS name, then its name, then
  its IP, not by its address alone. URLs reach renderers only through
  `data-nd-urls`, built with `uri_for` so tenant paths work.
- **New tables take their rows from a JSON data block.** The route sends
  `to_json(\@results)` to the HTML template and the plain `\@results` to
  the CSV template. The template writes
  `<script type="application/json" id="nd-results-<area>-<tag>">[% results.replace('<', '<') | none %]</script>`
  and names it in `data-nd-data`. Escaping `<` as `<` matters: a
  value containing `</script>` would otherwise end the block. Older
  templates that render `<tbody>` rows move to JSON when you change them
  substantially.
- **DataTables reads `data-search` from the first body row only.** A
  per-cell search value has to be on that row too
  (`xt/55-ports-search-shadow.t`).
- **A built table can hide and show a column it holds but cannot gain
  one.** Showing a column the server did not send means fetching the pane
  again.
- **Browser or server-side.** Load rows in the browser when the result is
  bounded, by one device or one search. Use server-side mode
  (`"serverSide": true`; model: `Report/NodeVendor.pm`) when a view can
  return the whole node, port or log table. Server-side mode needs:
  - a total SQL order (end with a unique key), or pages overlap and skip
    rows;
  - the same order the browser would sort in, so a re-sort agrees with
    the first page;
  - every searchable column searchable in SQL;
  - a registered renderer for every column, since rows arrive as JSON.
- **The cost of a large browser-loaded table is building its rows on the
  server, not the size of the page,** which compresses well. Measure the
  server's time before cutting markup.
- **A sort type nothing registers fails silently:** DataTables compares
  the cell text instead. Register a type with `DataTable.type()`, as
  `portsort.js` does.
- **Port order:** the Ports query returns rows in natural port order
  (`port_sortkey()`) and the browser still sorts with `portsort.js`. Keep
  both, so the first paint and a user's re-sort agree
  (`xt/11-port-sortkey.t`).

## Template Toolkit

- **Test hash membership with `exists`.** `hash.$key` falls back to Template
  Toolkit's hash methods when the key is missing, so a data key named
  `keys`, `values`, `each`, `list` or `items` reads as present. Use
  `hash.exists(key)`.

## Escaping

- Template Toolkit escapes every interpolation (`AUTO_FILTER` in
  `share/config.yml`). `| none` turns that off: use it only for a value
  that is already safe markup or a URL from `uri_for`, never for data read
  from the network or the database.
- CSV output is rendered with the filter off, so a CSV template must not
  carry markup.
- In renderers, escape with the `esc` helper in `netdisco-tables.js`. It
  does not escape the single quote, so never put an escaped value inside
  a single-quoted attribute (`xt/39-html-escaper.t`).
- Port descriptions, names, NetBIOS names and every other value a device
  reports are attacker-controlled. Treat them as untrusted text everywhere.

## Site-local templates are an interface

- Sites copy shipped templates into a local template directory and edit
  them; a copy shadows the shipped file. Changing what a template
  receives, or what a page expects from a template, can break those
  copies without any test failing here.
- When a change would break an older copy, keep the old variables working
  where you can, and add a rule to `lib/App/Netdisco/Util/SiteLocal.pm`
  so `netdisco-do checksitelocal` tells the admin what to change. The
  comment above its rules says what a rule needs, and
  `xt/47-site-local-checker.t` counts them.
- A plugin's own template, such as a `device_port_column.tt`, renders
  through the same engine and must keep working.

## Tests and verification

- Template change: run `xt/bin/regenerate-snapshots`, then read the diff
  before committing. A snapshot diff you did not expect is a finding.
- JavaScript change: run the `xt/js` files for the script you touched, by
  name. A new test file goes into `.github/workflows/frontend-tests.yml`.
- **JSON table:** test what the template emits by decoding the data block
  and the `data-nd-table` columns, and assert renderer names and arguments,
  not regexes over the HTML. Include a value containing `</script>` to show
  it cannot close the block.
- **Report:** check it through its page (`/report/<tag>?...`), not only its
  `/ajax/content/` route, which answers a parameter the page never forwards.
- **Source assertions are not behavior.** Many `xt/js` tests check source
  text. A claim that something works in the browser needs a browser: load
  the page and use it, and say in the PR which browser and what you did.
  Headless browsers hide paint timing, so check what a user sees, and when,
  in a headed one. Check hover, focus and layout in macOS Chrome or Safari
  as well as on Linux: tooltip dismissal and font metrics differ.
- **Performance:** measure the time from navigation until the table is
  built, server and browser separately, on a large device.

## Before you open the PR

- [ ] No jQuery, no script in a template fragment, no `history.pushState`;
      new code initializes after a swap.
- [ ] New colors are `--nd-*` tokens; the UI was checked in light and dark.
- [ ] Tables use existing renderers, one value per cell, rows from a JSON
      data block with `<` escaped.
- [ ] No `| none` on device or database data; renderers escape.
- [ ] A template change that sites may have copied has a
      `checksitelocal` rule.
- [ ] Snapshots regenerated and the diff read; new `xt/js` files listed in
      `frontend-tests.yml`; browser and actions named in the PR.
