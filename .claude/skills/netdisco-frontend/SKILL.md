---
name: netdisco-frontend
description: Use when changing or reviewing Netdisco's web frontend, meaning templates under share/views, scripts under share/public/javascripts, web plugins under lib/App/Netdisco/Web, or the DataTables a page builds, including tab, report and Ports tab work.
---

# Working on the Netdisco web frontend

The frontend was rebuilt in 2026: Bootstrap 5, htmx 4, DataTables 3 and no
jQuery. Older guides, forum answers and model training data describe the
jQuery frontend; none of it applies. The tests under `xt/js/` encode the
rules below, and each file's header comment says why its rule exists. Read
the header of any test your change touches before changing the test.

## Vendored libraries

- Bootstrap, DataTables, htmx, Font Awesome, force-graph,
  bootstrap5-toggle and Swagger UI are files under `share/public/`;
  nothing builds or installs them. `package.json` lists each with its
  version so scanners can see what ships.
- **Replacing one** is one commit (model: #1753):
  1. Copy in the release's distributed files unmodified, the same files
     as before. Swagger UI is a subset of `swagger-ui-dist`: keep the
     files already in `share/public/swagger-ui/`.
  2. Update its version in `package.json`.
  3. Update `xt/33-vendored-manifest.t`. A file that states its version is
     checked from that; for one pinned by checksum, set `sha256`
     (`sha256sum FILE`) and `pinned_for` to the new version.
  4. Add `* #NNNN upgrade the vendored <library> from <old> to <new>` to
     `Changes`.
  5. Run `prove -Ilib xt/33-vendored-manifest.t`, the `xt/js` tests, and
     open the pages that use the library in a browser.
- A pull request that changes `package.json` alone fails `xt/33` on
  purpose: the declared version must describe the shipped bytes.
- **retire.js** (`.github/workflows/retirejs.yml`) scans `share/public/` on
  every pull request and push to master, and fails on a library with a
  known advisory. Fix it by vendoring a fixed release. Only when none
  exists and the advisory does not apply to how Netdisco uses the
  library, waive that version in `.retireignore.json` with the reason,
  and remove the waiver when a fixed release is vendored.

## How a page loads

- A page (`share/views/device.tt`, `search.tt`, `report.tt`,
  `admintask.tt`) is a layout plus one sidebar form per tab. Each form
  carries `hx-get` to the tab's `/ajax/content/...` route, `hx-target` for
  its pane and `hx-sync` on the shared sidebar, so htmx keeps one request
  per page in flight and aborts the old one when the user switches tab.
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
- **Routes answer pane requests with `HX-Push-Url` or `HX-Replace-Url`**, so
  htmx owns browser history. Do not call `history.pushState` yourself
  (`xt/js/history-ownership.test.js`).
- **Initialize after a swap, not on page load.** A pane arrives by htmx swap
  long after `DOMContentLoaded`. Hook `htmx:after:swap` (see the listeners
  in `netdisco.js`), or register with `ndPages` and let `netdisco.js` call
  your page's `ready()`.
- **htmx binds triggers once, when it processes a node.** Rows that
  DataTables draws later, on paging or sorting, have no htmx listeners, and
  a `once` trigger is spent when the event fires, before the request, so a
  failed fetch leaves the element inert. For an element inside a table,
  give it `hx-trigger="none"` and have a delegated listener on `document`
  call `htmx.ajax(verb, url, {source: elt})`, as
  `netdisco-deferred-nodes.js` does for the Ports tab's node boxes.
- **Pane settling:** `netdisco.js` hides a pane before swap
  (`nd_pane-settling`) and reveals it once its table is built. Whatever
  adds that class must be gated on the same condition as whatever removes
  it, or the pane stays hidden (`xt/js/pane-settling.test.js`).

## Where JavaScript goes

- **All JavaScript is static, in `share/public/javascripts/`.** A template
  fragment carries no `<script>` except a JSON data block
  (`<script type="application/json" id="...">`), and Template Toolkit
  generates no code. This keeps every script inside CodeQL's analysis and
  inside the `xt/js` tests (`no-fragment-scripts.test.js`,
  `view-templates.test.js`).
- **No jQuery**, in any shipped script or the layout
  (`no-jquery.test.js`). Use the DOM API and Bootstrap 5's own JavaScript.
- **Page scripts register with `ndPages`** (declared in `netdisco.js`; see
  `netdisco-admin.js`), so `netdisco.js` does not need to know which pages
  exist.
- **Authored functions carry JSDoc** with a description, parameters and
  return value, as in `netdisco-request.js`.

## Bootstrap components and events

- **Tooltips:** macOS Chrome fires no `mouseleave` when an element is
  hidden under a pointer that has not moved, so its tooltip is left
  stranded at the top left of the window. Linux Chromium and Firefox do
  not show this, so CI cannot either. Hide an element that may be showing
  a tooltip only through `hideWithTooltip()` in `netdisco.js`
  (`xt/js/tooltip-dismissal.test.js`).
- **Popovers:** before a swap, call `hide()`, never `dispose()`. Bootstrap
  finishes a hide after its transition and reads the instance again, so
  `dispose()` on a tip caught mid-hide throws. `removeStrandedPopovers()`
  cleans up the rest (`xt/js/stranded-popovers.test.js`).
- **Bootstrap fires events only on transitions.** A component rendered
  open fires no `show` event, so initialize from its initial state as well
  as on its events (`xt/js/statistics-panel.test.js`).
- **Delegated listeners:** bind once on `document`, not on each element,
  because panes are swapped out. In the handler, `closest()` returns null
  for an element outside the container you expect, such as a button not in
  a table row; handle that case (`xt/js/admin-button-dispatch.test.js`).
- **High-frequency events:** save or post when a drag or gesture settles,
  not on every `mousemove` (`xt/js/netmap-autosave.test.js`).
- **Visibility:** a closed `<details>` hides its contents without
  `display: none`, so `offsetParent` still reports an element. Use
  `element.checkVisibility()`.

## Themes and styling

- **Bootstrap first.** Use Bootstrap 5.3's classes, utilities and
  components before writing CSS; add a rule to
  `share/public/css/netdisco.css` only when no Bootstrap class does the
  job. Colors come from Bootstrap's CSS variables (`var(--bs-...)`),
  never a literal color in a template, script or rule.
- **Netdisco's own colors are `--nd-*` tokens**, defined in `:root` in
  `netdisco.css` and mapped onto Bootstrap's variables so they follow the
  color mode. A new colored element gets a token there:
  `xt/121-theme-tokens.t` fails a color written anywhere else.
- **Themes are Bootstrap color modes.** `web_theme` (default `auto`)
  picks one: `light` is Bootstrap's own colors, `dark` is
  `themes/dark.css`, `auto` follows the browser between the two, and
  `classic` is Netdisco's colors from before Bootstrap 5. A theme file
  sets Bootstrap's variables and the `--nd-*` tokens under
  `[data-bs-theme="<name>"]`; `App::Netdisco::Web::Theme` warns at startup
  when a file has no rule scoped to its own name.
- **Writing a theme:** copy `share/public/css/themes/classic.css` (its
  header explains the steps): to `nd-site-local/share/themes/<name>.css`
  for one site, or beside it in `share/public/css/themes/` to ship one.
  Replace `classic` in every selector and keep only the sections you
  need. Names are letters, digits, `-` and `_`; `light` and `auto` are
  reserved.
- **Shipped themes are tested:** `xt/117` checks every Bootstrap variable
  a theme sets still exists, and `xt/122` checks every `--nd-*` token it
  sets is still defined, and measures contrast for some colors in light
  and dark. When you add a token, set it in `dark.css` too if Bootstrap's
  dark variables cannot express it.
- A canvas cannot see stylesheets: the network map's colors reach it only
  through the `--nd-netmap-*` tokens its script reads
  (`xt/js/netmap-theme-colors.test.js`).
- Check new UI in light and dark.

## Tables

- **Every DataTable is built by `netdisco-tables.js`** from a
  `data-nd-table` attribute holding a DataTables options object. A
  renderer, `drawCallback` or `initComplete` is named in that file's
  registry and referenced by name from the JSON. Add a renderer there,
  never as an inline closure in a template
  (`xt/js/tables-registry.test.js`). The header comment in that file is the
  contract for the attribute and its siblings (`data-nd-data`,
  `data-nd-urls`).
- **Use a renderer that exists before adding one.** The registry already
  covers most cells: `escape`, `number`, `join` (`key`, `with`),
  `deviceLink` (`tab`, `label: {dns, name, ip}`), `searchDeviceLink`,
  `searchLink` (`tab`), `subnetLink`, `reportLink` (`report`, `param`,
  `key`, `show`, `blankText`), `devicePortsLink` and others; each one's
  JSDoc lists its arguments. A column names its renderer with the field it
  renders: `{"data":"subnet","render":"subnetLink"}`. Add a renderer only
  for a cell no combination of these can draw, with a test in
  `xt/js/tables-registry.test.js`.
- **One value or one link per cell.** When a cell would need several links,
  or a sentence with links inside it, change what a row is (one row per
  device, VRF or port) rather than build a composite cell, in a template or
  in a new renderer. Every column then maps to an existing renderer, and
  sorting and searching work per value.
- **Empty values:** `deviceLink` and `subnetLink` always draw a link, so an
  empty cell becomes a link to `q=null`. Use them only on columns that are
  never empty, or use `searchDeviceLink` with `notSet`. `reportLink` sends
  `blank` for an empty key and shows `blankText`; given an array key it
  sends the values comma-joined (`%2C`), so the receiving route must split
  on commas.
- **Labels and URLs:** label a device by its DNS name, then its name, then
  its IP (`deviceLink`'s `label`), not by its address alone. URLs reach
  renderers only through `data-nd-urls`, built with `uri_for` so tenant
  paths work.
- **New tables take their rows from a JSON data block.** The route sends
  `to_json(\@results)` to the HTML template and the plain `\@results` to
  the CSV template. The template writes
  `<script type="application/json" id="nd-results-<area>-<tag>">[% results.replace('<', '\u003c') | none %]</script>`
  and names it in `data-nd-data`. Escaping `<` as `\u003c` matters: a
  value containing `</script>` would otherwise end the block. About 18
  older templates still render `<tbody>` rows in Template Toolkit; move one
  to JSON when you change it substantially. Use rendered rows only where a
  cell's markup has no renderer and cannot be split into columns.
- **DataTables reads `data-search` from the first body row only.** A
  per-cell search value has to be on that row too, or the column searches
  the cell's display text (`xt/55-ports-search-shadow.t`).
- **A built table can hide and show a column it holds
  (`column().visible()`) but cannot gain one.** Showing a column the
  server did not send means fetching the pane again.
- **Two ways a table gets its rows.** Most tables arrive whole with the
  pane's HTML, as a JSON data block (`data-nd-data`) or, in older
  templates, as rendered `<tbody>` rows, and DataTables sorts, pages and
  searches in the browser, with `deferRender` so only the visible page is
  drawn. A few reports that
  can return a whole table (Node Vendor, NetBIOS, Module Inventory, PoE
  Status, AP Radio Channel Power, User Log) use server-side mode instead:
  `"serverSide": true` and an `ajax` URL in `data-nd-table`, and a `/data`
  route that returns JSON for each draw from `$rs->get_datatables_data`
  and `get_datatables_filtered_count` (`DB/ResultSet.pm`), as
  `Report/NodeVendor.pm` does.
- **Choosing:** load in the browser when the result is bounded, by one
  device or one search, so sorting and searching are instant. Use
  server-side when a report can return the whole node, port or log table.
- **Server-side mode has requirements** a browser-loaded table does not:
  - each page is a slice of the SQL `ORDER BY`, so the order must be total
    (end with a unique key) or pages overlap and skip rows;
  - it must sort the way the browser would, so a re-sort agrees with the
    first page: for ports that is the `port_sortkey()` SQL function, which
    matches `portsort.js` (`xt/js/portsort.test.js`);
  - every searchable column must be searchable in SQL, including any
    per-cell `data-search` value;
  - the browser draws every cell: rows arrive as JSON, so each column needs
    a registered renderer in `netdisco-tables.js`, and cell markup built in
    a template (as the Ports tab's is, `port_nodes.tt` among it) has to move
    into renderers first;
  - renderers see one page of rows, and the counts come from SQL.
- **The cost of a large browser-loaded table is building its rows on the
  server, not the size of the page,** which compresses well. Measure the
  server's time before cutting markup.
- **A sort type nothing registers fails silently:** DataTables compares
  the cell text instead, and every page still renders. Register a type
  with `DataTable.type()`, as `portsort.js` does
  (`xt/js/sort-types.test.js`).
- **Port order:** the Ports query returns rows in natural port order
  (the `port_sortkey()` SQL function, see `DB/ResultSet/DevicePort.pm`)
  and the browser still sorts with `portsort.js`.
  Keep both, so the first paint and a user's re-sort agree
  (`xt/js/portsort.test.js`).

## Escaping

- Template Toolkit escapes every interpolation (`AUTO_FILTER:
  html_entity` in `share/config.yml`). `| none` turns that off: use it only
  for a value that is already safe markup or a URL from `uri_for`, never
  for data read from the network or the database.
- CSV output is rendered with the filter off (`Web.pm`), so a CSV template
  must not carry markup.
- In renderers, escape with `DataTable.util.escapeHtml` (the `esc` helper
  in `netdisco-tables.js`). It does not escape the single quote, so never
  put an escaped value inside a single-quoted attribute
  (`xt/39-html-escaper.t`).
- Port descriptions, names, NetBIOS names and every other value a device
  reports are attacker-controlled. Treat them as untrusted text everywhere.

## Site-local templates are an interface

- Sites copy shipped templates into a `template_paths` directory or
  `~/nd-site-local/share/views` and edit them. A copy shadows the shipped
  file. Changing what a template receives, or what a page expects from a
  template, can break those copies without any test failing here.
- When a change would break an older copy, keep the old variables working
  where you can, and add a rule to `lib/App/Netdisco/Util/SiteLocal.pm`
  so `netdisco-do checksitelocal` tells the admin what to change. A rule
  names the release it ships in; `xt/47-site-local-checker.t` counts the
  rules and needs updating with them.
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
  built, server and browser separately, on a large device. For the Ports
  tab the cost is mostly building rows (Perl and DBIx::Class), then the
  browser building the table; fragment size matters less than it looks,
  because responses are compressed.
