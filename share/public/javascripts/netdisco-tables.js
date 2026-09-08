// Every DataTable on the site is built here, from a data-nd-table attribute
// on the <table>, rather than by a script inside the fragment that delivered
// it. A fragment can then carry no JavaScript at all, which is what lets
// CodeQL see all of ours.
//
// The data-nd-table attribute is a DataTables options object: columns,
// columnDefs, targets, order, paging and the rest keep DataTables' own
// meaning and are passed through unchanged, so the DataTables option
// reference is their specification. Two keys are consumed here and never
// reach DataTables: "defaults": false skips the shared options, which are
// the DataTables options every table starts from and live in defaults()
// below, and "customReport" keeps a custom report's column order out of the
// saved table state. Three sibling attributes complete the contract:
// data-nd-urls holds the URL prefixes the renderers need, data-nd-data names
// the id of the application/json block holding the rows, and data-nd-admin
// tells the subnet renderer whether to show the admin tools.
//
// JSON cannot carry a function, so a column's render and a table's
// drawCallback or initComplete are named here and referenced by name. Each
// entry is a factory: it takes the arguments the JSON gives it and the
// table's URL prefixes, and returns the function DataTables calls.

const ndTables = (function () {
  const esc = function (s) {
    return DataTable.util.escapeHtml(s == null ? '' : String(s));
  };
  const enc = encodeURIComponent;
  const get = function (row, dotted) {
    return String(dotted)
      .split('.')
      .reduce(function (o, k) {
        return o == null ? o : o[k];
      }, row);
  };
  const link = function (href, text) {
    return '<a href="' + href + '">' + text + '</a>';
  };

  // DataTable.render.text() and .number() return an object keyed by render
  // type (display, filter, ...), falling back to the raw value for a type
  // they don't name, rather than a single function; this makes that shape
  // callable like every other entry in RENDERERS.
  const byType = function (spec) {
    return function (data, type) {
      return (
        spec[type] ||
        function (d) {
          return d;
        }
      )(data);
    };
  };

  // Device label as netdisco shows it everywhere: dns, else name, else ip.
  // args.dns, args.name and args.ip name the row keys, each optional. A
  // caller that itself needs a "name" key for something other than a row
  // key (deviceLink's dispatch key is "name" too) cannot also write a row
  // key literally called "name" in the same JSON object: JSON.parse keeps
  // only the last of two identical keys. Such a caller nests dns/name/ip
  // under args.label instead, a second object with no such collision.
  //
  // The closures this replaces each read a fixed, different subset of
  // dns/name/ip (some never looked at name at all), so naming any one of the
  // three restricts the cascade to only the named tiers, still tried in dns,
  // name, ip order. Naming none is a caller with no such history to match,
  // so it gets the full three-tier fallback.
  const deviceLabel = function (args, row, fallback) {
    const a = args.label || args;
    const tiers = a.dns || a.name || a.ip ? [a.dns, a.name, a.ip] : ['dns', 'name', 'ip'];
    let value;
    tiers.forEach(function (key) {
      if (!value && key) value = get(row, key);
    });
    return value || fallback;
  };
  const withQuery = function (base, q) {
    return base + (base.indexOf('?') === -1 ? '?' : '&') + q;
  };

  // Every renderer needing a URL prefix reads it through here, so a fragment
  // missing a data-nd-urls key fails loudly, naming the key and the
  // renderer, instead of building an href with the literal text "undefined".
  const urlFor = function (urls, name, rendererName) {
    const url = urls[name];
    if (url == null) throw new Error('renderer ' + rendererName + ' needs data-nd-urls key "' + name + '"');
    return url;
  };

  // The book marker an inactive node carries: inside the link text with
  // args.mark, beside it with args.archived, absent for an active row.
  const archivedMark = function (args, row) {
    if (!((args.archived || args.mark) && !row.active)) return '';
    if (args.mark) return '&nbsp;&nbsp;<i class="fas fa-book text-warning"></i> ';
    return '&nbsp;<i class="fas fa-book text-warning"></i>&nbsp;';
  };

  const RENDERERS = {
    /**
     * Returns the cell value unchanged, or an empty string when the value is null or undefined.
     * @returns {Function} the DataTables render function
     */
    raw: function () {
      return function (data) {
        return data == null ? '' : data;
      };
    },
    /**
     * Escapes the cell value as HTML text for every render type, via the vendored text renderer.
     * @returns {Function} the DataTables render function
     */
    escape: function () {
      return byType(DataTable.render.text());
    },
    /**
     * Formats a numeric cell with thousands separators. The vendored formatter bakes in
     * one fixed decimal count per instance, but a column such as devicepoestatus's
     * wattage readings mixes whole watts with one-decimal values row by row, so the
     * precision is read off each value's own string form instead of fixed at build
     * time. Non-numeric and null values pass through unformatted either way, by the
     * vendored formatter's own guard.
     * @param {object} args args.precision, when given, forces that precision for every row instead of reading it per value
     * @returns {Function} the DataTables render function
     */
    number: function (args) {
      const instances = {};
      const forPrecision = function (p) {
        return instances[p] || (instances[p] = DataTable.render.number(',', '.', p));
      };
      const decimalPlaces = function (data) {
        const match = /\.(\d+)$/.exec(String(data));
        return match ? match[1].length : 0;
      };
      return function (data, type) {
        const precision = args.precision != null ? args.precision : decimalPlaces(data);
        return byType(forPrecision(precision))(data, type);
      };
    },
    /**
     * Renders a truthy cell as "Yes" and a falsy cell as "No".
     * @returns {Function} the DataTables render function
     */
    yesNo: function () {
      return function (data) {
        return data ? 'Yes' : 'No';
      };
    },
    /**
     * Formats a cell as YYYY-MM-DD HH:mm. The server sends local wall clock
     * already in sort order as text, so this slices the string rather than
     * constructing a Date: there is no timezone here to get wrong.
     * @returns {Function} the DataTables render function
     */
    dateTime: function () {
      return function (data, type) {
        if (data == null) return '';
        const text = String(data).replace('T', ' ');
        return type === 'display' || type === 'filter' ? esc(text.slice(0, 16)) : text;
      };
    },
    /**
     * Upper-cases the first character of the escaped cell text, leaving the rest unchanged.
     * @returns {Function} the DataTables render function
     */
    capitalize: function () {
      return function (data) {
        const s = data == null ? '' : String(data);
        return esc(s.charAt(0).toUpperCase() + s.slice(1));
      };
    },
    /**
     * Joins the row array named by args.key into one string, escaping each element.
     * @param {object} args args.key names the row array to join; args.with overrides the default "<br />" separator
     * @returns {Function} the DataTables render function
     */
    join: function (args) {
      if (!args.key) throw new Error('renderer join needs a "key" naming the row array to join');
      return function (data, type, row) {
        return (get(row, args.key) || []).map(esc).join(args.with || '<br />');
      };
    },
    /**
     * Renders the row's device label (dns, else name, else ip) as escaped plain text, with no link.
     * @param {object} args the dns/name/ip label selection, as read by deviceLabel
     * @returns {Function} the DataTables render function
     */
    deviceName: function (args) {
      return function (data, type, row) {
        return esc(deviceLabel(args, row, data));
      };
    },

    /**
     * Links to a device's ports tab. Sorting and filtering see only the escaped cell
     * value, unless args.always asks for the link on every render type as the closures
     * this replaced did.
     * @param {object} args args.q and args.f each name a row key, or "data" for the cell
     *   itself: q for the device address, f for the port. args.qFallback names a row
     *   key used for q when that key's own value is empty. args.flags is a literal
     *   query suffix; args.descr adds a second line from a row key; args.class sets the
     *   anchor's classes; args.text names a row key shown instead of the cell;
     *   args.number formats the shown text with thousands separators; args.always
     *   renders the link for every render type
     * @param {{[key: string]: string}} urls the URL prefixes from data-nd-urls; reads "device_ports"
     * @returns {Function} the DataTables render function
     */
    devicePortsLink: function (args, urls) {
      if (args.text && args.number) throw new Error('renderer devicePortsLink: "text" and "number" cannot both be set');
      const portsUrl = urlFor(urls, 'device_ports', 'devicePortsLink');
      const rowKeyOrCell = function (row, rowKey, cellValue) {
        return rowKey === 'data' ? cellValue : get(row, rowKey);
      };
      const numberFormat = args.number ? DataTable.render.number(',', '.', 0) : null;
      return function (data, type, row) {
        const text = esc(data);
        if (type !== 'display' && !args.always) return text;
        const deviceRowKey = args.q || 'ip';
        const portRowKey = args.f;
        let qValue = rowKeyOrCell(row, deviceRowKey, data);
        if (!qValue && args.qFallback) qValue = get(row, args.qFallback);
        let href = portsUrl + '&q=' + enc(qValue);
        if (portRowKey) href += '&f=' + enc(rowKeyOrCell(row, portRowKey, data));
        if (args.flags) href += '&' + args.flags;
        const cls = args.class ? ' class="' + args.class + '"' : '';
        let shown = text;
        if (args.text) shown = esc(get(row, args.text));
        else if (numberFormat) shown = esc(numberFormat.display(data));
        const extra = args.descr ? '<br />' + esc(get(row, args.descr)) : '';
        return '<a' + cls + ' href="' + href + '">' + shown + '</a>' + extra;
      };
    },

    /**
     * Links to a device's ports tab, labeled with the device name rather than the
     * cell, for every render type.
     * @param {object} args args.q and args.f name row keys (f optional), or "data" for
     *   the cell itself; args.flags appends fixed query parameters; args.suffix names
     *   a row key, or "data" for the cell, shown in parentheses after the name, with
     *   args.suffixSpace adding a space before them; args.dns, args.name, args.ip pick
     *   the label keys
     * @param {{[key: string]: string}} urls the URL prefixes from data-nd-urls; reads "device_ports"
     * @returns {Function} the DataTables render function
     */
    devicePortsLinkNamed: function (args, urls) {
      const portsUrl = urlFor(urls, 'device_ports', 'devicePortsLinkNamed');
      return function (data, type, row) {
        const deviceRowKey = args.q;
        const portRowKey = args.f;
        const deviceAddress = deviceRowKey === 'data' || !deviceRowKey ? data : get(row, deviceRowKey);
        let href = portsUrl + '&q=' + enc(deviceAddress);
        if (portRowKey) href += '&f=' + enc(portRowKey === 'data' ? data : get(row, portRowKey));
        if (args.flags) href += '&' + args.flags;
        let text = esc(deviceLabel(args, row, data));
        if (args.suffix)
          text +=
            (args.suffixSpace ? ' ' : '') + '(' + esc(args.suffix === 'data' ? data : get(row, args.suffix)) + ')';
        return link(href, text);
      };
    },

    /**
     * Links to the device page (uri_for('/device')), labeled with the device name,
     * for every render type.
     * @param {object} args args.tab adds a tab to the link; args.suffix names a row key
     *   shown in parentheses after the name; args.dns, args.name, args.ip (or the same
     *   keys under args.label) pick the label keys
     * @param {{[key: string]: string}} urls the URL prefixes from data-nd-urls; reads "device"
     * @returns {Function} the DataTables render function
     */
    deviceLink: function (args, urls) {
      const deviceUrl = urlFor(urls, 'device', 'deviceLink');
      return function (data, type, row) {
        const href = withQuery(deviceUrl, (args.tab ? 'tab=' + args.tab + '&' : '') + 'q=' + enc(data));
        let text = esc(deviceLabel(args, row, data));
        if (args.suffix) text += ' (' + esc(get(row, args.suffix)) + ')';
        return link(href, text);
      };
    },

    /**
     * Links to the device search, for every render type; args.notSet's plain text is
     * likewise shown for every type when the cell is empty.
     * @param {object} args args.also repeats the value under a second query parameter
     *   name; args.label picks the label keys (dns, name, ip) instead of the cell;
     *   args.notSet is shown instead of a link when the cell is empty
     * @param {{[key: string]: string}} urls the URL prefixes from data-nd-urls; reads "search_device"
     * @returns {Function} the DataTables render function
     */
    searchDeviceLink: function (args, urls) {
      const searchDeviceUrl = urlFor(urls, 'search_device', 'searchDeviceLink');
      return function (data, type, row) {
        if ((data == null || data === '') && args.notSet) return args.notSet;
        const href = searchDeviceUrl + '&q=' + enc(data) + (args.also ? '&' + args.also + '=' + enc(data) : '');
        const text = esc(args.label ? deviceLabel(args.label, row, data) : data);
        return link(href, text);
      };
    },

    /**
     * Links to the node search. Sort and filter see the escaped cell text alone unless
     * args.always builds the link for every render type; the cell is also shown plain
     * (no link) whenever it is empty or, when args.onlyIf is given, that row key is falsy.
     * @param {object} args args.upper shows the MAC upper-cased; args.archived adds the
     *   archived flag and marker for an inactive row; args.mark appends the marker
     *   inside the link without the flag; args.domainPrefix prepends the NetBIOS
     *   domain; args.onlyIf names a row key that must be truthy for the link to render
     *   at all; args.always renders the link for every render type, not just display
     * @param {{[key: string]: string}} urls the URL prefixes from data-nd-urls; reads "search_node"
     * @returns {Function} the DataTables render function
     */
    searchNodeLink: function (args, urls) {
      const searchNodeUrl = urlFor(urls, 'search_node', 'searchNodeLink');
      return function (data, type, row) {
        const shown = esc(args.upper ? String(data == null ? '' : data).toUpperCase() : data);
        if (type !== 'display' && !args.always) return shown;
        if (data == null || data === '') return shown;
        if (args.onlyIf && !get(row, args.onlyIf)) return shown;
        const flag = args.archived && !row.active ? '&archived=on' : '';
        const prefix = args.domainPrefix && row.domain ? esc('\\\\' + row.domain + '\\') : '';
        return prefix + link(searchNodeUrl + '&q=' + enc(data) + flag, shown + archivedMark(args, row));
      };
    },

    /**
     * report/ipinventory ip column: for the display render type, a node link when the
     * address belongs to a known node, a device link when it was only seen on a
     * device, plain text when never seen (row.time_last unset); every other render
     * type sees the escaped cell text alone.
     * @param {object} args unused; kept for the renderer factory signature
     * @param {{[key: string]: string}} urls the URL prefixes from data-nd-urls; reads "search_node" and "search_device"
     * @returns {Function} the DataTables render function
     */
    ipInventoryAddress: function (args, urls) {
      // Which URL is needed depends on the row, not the column, so each is
      // resolved only on the branch that actually uses it.
      return function (data, type, row) {
        const text = esc(data);
        if (type !== 'display' || !row.time_last) return text;
        if (row.node) {
          const flag = row.active ? '' : '&archived=on';
          const mark = row.active ? '' : '&nbsp;<i class="fas fa-book text-warning"></i>&nbsp;';
          return link(urlFor(urls, 'search_node', 'ipInventoryAddress') + '&q=' + enc(data) + flag, text + mark);
        }
        return link(urlFor(urls, 'search_device', 'ipInventoryAddress') + '&q=' + enc(data), text);
      };
    },

    /**
     * Links to a search tab with q set to the cell. Ignores the render type, so every
     * type sees the anchor markup.
     * @param {object} args args.tab names the search tab; args.list renders an array of
     *   values as a comma separated list of links instead of a single link
     * @param {{[key: string]: string}} urls the URL prefixes from data-nd-urls; reads "search"
     * @returns {Function} the DataTables render function
     */
    searchLink: function (args, urls) {
      const searchUrl = urlFor(urls, 'search', 'searchLink');
      const one = function (v) {
        return link(withQuery(searchUrl, 'tab=' + args.tab + '&q=' + enc(v)), esc(v));
      };
      return function (data) {
        return args.list ? (data || []).map(one).join(', ') : one(data);
      };
    },

    /**
     * Links to a report carrying one query parameter, for every render type. A caller
     * naming no blankText gets an empty label rather than the sent "blank" token,
     * matching the closures this replaced.
     * @param {object} args args.report names the URL in data-nd-urls, args.param the
     *   parameter; args.key takes the value from a row key instead of the cell;
     *   args.show names a row key for the label; args.blank is sent when the value is
     *   empty; args.blankText, when given, is shown instead of empty text;
     *   args.capitalize upper-cases the label's first letter
     * @param {{[key: string]: string}} urls the URL prefixes from data-nd-urls; reads the URL named by args.report
     * @returns {Function} the DataTables render function
     */
    reportLink: function (args, urls) {
      const reportUrl = urlFor(urls, args.report, 'reportLink');
      return function (data, type, row) {
        const value = args.key ? get(row, args.key) : data;
        const empty = value == null || value === '';
        const sent = empty ? args.blank || 'blank' : value;
        const shown = args.show ? get(row, args.show) : value;
        let text = shown == null || shown === '' ? args.blankText || '' : shown;
        text = String(text);
        if (args.capitalize) text = text.charAt(0).toUpperCase() + text.slice(1);
        return link(withQuery(reportUrl, args.param + '=' + enc(sent)), esc(text));
      };
    },

    /**
     * search/port ip column: links to the address and port, with the device name
     * beneath, for every render type.
     * @param {object} args unused; kept for the renderer factory signature
     * @param {{[key: string]: string}} urls the URL prefixes from data-nd-urls; reads "device_ports"
     * @returns {Function} the DataTables render function
     */
    searchPortLink: function (args, urls) {
      const portsUrl = urlFor(urls, 'device_ports', 'searchPortLink');
      return function (data, type, row) {
        const name = get(row, 'device.dns') || get(row, 'device.name');
        const below = name ? '<br>(' + esc(name) + ')' : '';
        return (
          link(portsUrl + '&q=' + enc(data) + '&f=' + enc(row.port), esc(data) + ' [' + esc(row.port) + ']') + below
        );
      };
    },

    /**
     * Renders an elapsed-time cell, or "Never" when it is empty: a trailing ":00"
     * becomes " mins", and any remaining ":" becomes " hours ". For non-display render types, sorts and
     * filters on the raw timestamp named by args.stamp instead of the formatted text.
     * @param {object} args args.stamp names the row key carrying the raw timestamp used for sorting and filtering
     * @returns {Function} the DataTables render function
     */
    age: function (args) {
      return function (data, type, row) {
        if (type !== 'display') return get(row, args.stamp);
        return esc(data || 'Never')
          .replace(/:00$/, ' mins')
          .replace(':', ' hours ');
      };
    },
    /**
     * report/apradiochannelpower power column: renders the milliwatt reading alongside
     * row.power2, its dBm equivalent computed by the view; renders nothing when
     * power2 is null or zero, the view's own guard for a non-positive power reading.
     * @returns {Function} the DataTables render function
     */
    powerPair: function () {
      return function (data, type, row) {
        return row.power2 ? esc(data) + ' / ' + esc(row.power2) : '';
      };
    },
    /**
     * Renders a NetBIOS domain cell, substituting "(Blank Domain)" when it is empty.
     * @returns {Function} the DataTables render function
     */
    blankDomain: function () {
      return function (data) {
        return esc(data || '(Blank Domain)');
      };
    },
    /**
     * Renders the row's NetBIOS user, substituting "[No User]" when it is empty.
     * @returns {Function} the DataTables render function
     */
    nbUser: function () {
      return function (data, type, row) {
        return esc(row.nbuser || '[No User]');
      };
    },
    /**
     * Renders a port's admin/operational state as one icon: a cross when admin down, a
     * red down arrow when admin up but not operationally up or dormant, otherwise a
     * green up arrow.
     * @returns {Function} the DataTables render function
     */
    portUpIcon: function () {
      return function (data, type, row) {
        if (row.up_admin !== 'up') return '<i class="fas fa-xmark"></i>';
        if (row.up !== 'up' && row.up !== 'dormant') return '<i class="fas fa-arrow-down text-danger"></i>';
        return '<i class="fas fa-angle-up text-success"></i>';
      };
    },
    /**
     * device/addresses subnet: links to the device search, for every render type,
     * adding inventory and discover shortcuts for an admin viewer. Whether the viewer
     * is admin arrives on the table itself, via its data-nd-admin attribute.
     * @param {object} args unused; kept for the renderer factory signature
     * @param {{[key: string]: string}} urls the URL prefixes from data-nd-urls; reads
     *   "search_device", and "uri_base" only when the viewer is an admin
     * @param {HTMLTableElement} table the table element, read for its data-nd-admin flag
     * @returns {Function} the DataTables render function
     */
    subnetLink: function (args, urls, table) {
      const admin = table.dataset.ndAdmin === '1';
      // uri_base is only ever needed for the admin tool links, so it is only
      // required of data-nd-urls when this table's viewer is an admin.
      const uriBase = admin ? urlFor(urls, 'uri_base', 'subnetLink') : null;
      const searchDeviceUrl = urlFor(urls, 'search_device', 'subnetLink');
      return function (data) {
        const tools = admin
          ? '<a class="nd_stealth-link" href="' +
            uriBase +
            '/report/ipinventory?subnet=' +
            enc(data) +
            '"><i rel="tooltip" data-bs-placement="left" data-bs-title="Node Inventory" class="fas fa-laptop"></i></a> ' +
            '<a class="nd_stealth-link nd_node-ext-link" href="' +
            uriBase +
            '/?device=' +
            enc(data) +
            '"><i rel="tooltip" data-bs-placement="left" data-bs-title="Discover Devices here" class="fas fa-magnifying-glass"></i></a>&nbsp;'
          : '';
        return tools + link(searchDeviceUrl + '&q=' + enc(data) + '&ip=' + enc(data), esc(data));
      };
    }
  };

  // toggle is bound with addEventListener rather than jQuery's .bind; $(this)
  // still resolves because the browser calls the handler with the clicked
  // element as its context either way.
  const collapse = {
    // temporarily disable datatables paging
    // returns [current_page_length, current_page_index]
    disablePaging: function () {
      $.fn.dataTable.ext.search.pop();
      const plen = $('#dp-data-table').DataTable().page.len();
      const pnum = $('#dp-data-table').DataTable().page();
      $('#dp-data-table').DataTable().page.len(-1).draw(true);
      return [plen, pnum];
    },

    // restore the datatables pagination and page number
    restorePage: function (plen, pnum) {
      $('#dp-data-table').DataTable().page.len(plen).draw(true);
      $('#dp-data-table').DataTable().page(pnum).draw(false);
    },

    // install our row filter for datatables row group toggle
    pushFilter: function () {
      $.fn.dataTable.ext.search.push(function (settings, data, dataIndex) {
        const row = $($('#dp-data-table').DataTable().row(dataIndex).node());
        if (!row.data('collapsed-group')) {
          return true;
        }
        return row.attr('data-is-collapsed') === 'false';
      });
    },

    // onclick handler
    // toggles visibility of a group of datatables rows
    // clicked element has the group name as data-collapsed-group
    toggle: function () {
      const groupname = $(this).attr('data-collapsed-group');
      const [plen, pnum] = ndTables.collapse.disablePaging();

      // groupname is not in a class selector due to port name characters
      $('tr.nd_collapsible').each(function () {
        if ($(this).attr('data-collapsed-group') === groupname) {
          if ($(this).attr('data-is-collapsed') === 'true') {
            $(this).attr('data-is-collapsed', 'false');
          } else {
            $(this).attr('data-is-collapsed', 'true');
          }
        }
      });

      ndTables.collapse.pushFilter();
      ndTables.collapse.restorePage(plen, pnum);

      const icon = $(this).find('i');
      icon.toggleClass('fa-list-ol fa-arrow-up-wide-short fa-rotate-180');
    }
  };

  // Binds one delegated click listener on a grouped table's tbody, toggling
  // its column-0 order between ascending and descending. drawCallback runs
  // on every redraw, so the table itself carries the guard; a later
  // grouping callback can call this the same way groupRows does.
  const bindGroupOrderToggle = function (api) {
    const table = api.table().node();
    if (table.dataset.ndGroupToggle) return;
    table.dataset.ndGroupToggle = '1';
    api
      .table()
      .body()
      .addEventListener('click', function (e) {
        if (!e.target.closest('tr.group')) return;
        const current = api.order()[0];
        api.order([0, current[0] === 0 && current[1] === 'asc' ? 'desc' : 'asc']).draw();
      });
  };

  // Shared by groupRows and groupDeviceRows: inserts one header row above
  // the first row of each run of equal column-0 values. labelFor(group, row)
  // gets the column-0 value and a lazy getter for the full row, since
  // groupRows' label is a function of the former alone and groupDeviceRows'
  // of the latter alone; the getter keeps groupRows from ever calling
  // api.row() at all.
  const groupHeaders = function (api, colspan, labelFor) {
    const rows = api.rows({ page: 'current' }).nodes();
    let last = null;
    api
      .column(0, { page: 'current' })
      .data()
      .each(function (group, i) {
        if (last !== group) {
          // labelFor escapes its fields, or passes cell HTML the server already escaped
          // eslint-disable-next-line no-unsanitized/method
          rows[i].insertAdjacentHTML(
            'beforebegin',
            '<tr class="group"><td colspan="' +
              colspan +
              '">' +
              labelFor(group, function () {
                return api.row(i).data();
              }) +
              '</td></tr>'
          );
          last = group;
        }
      });
  };

  const CALLBACKS = {
    /**
     * Inserts one group header row above each run of equal first-column values,
     * repeating the first column's own text as the group's label.
     * @param {object} args args.colspan is the visible column count; the group value is
     *   escaped by default, matching a data-nd-data JSON row (raw text), but args.html
     *   true skips escaping for a DOM-sourced table, whose cells DataTables reads as
     *   already-rendered HTML; args.toggleOrder makes a click on a group header flip the
     *   sort direction
     * @returns {Function} the DataTables drawCallback function
     */
    groupRows: function (args) {
      const renderGroup = args.html
        ? function (v) {
            return v;
          }
        : esc;
      return function () {
        const api = this.api();
        groupHeaders(api, args.colspan, function (group) {
          return renderGroup(group);
        });
        if (args.toggleOrder) bindGroupOrderToggle(api);
      };
    },

    /**
     * report/apradiochannelpower and report/devicepoestatus: inserts one group header
     * row above each run of equal first-column values, built as a whole-row device
     * label rather than the escaped value of column 0, since column 0 alone does not
     * carry enough of the row to build it.
     * @param {object} args args.colspan and args.toggleOrder as groupRows; there is no
     *   args.html, since the label is always built from row fields and escaped itself,
     *   never from an already-rendered cell. args.nameKey names the row key read when
     *   dns is absent: report/apradiochannelpower and report/devicepoestatus key it
     *   differently, device_name and name respectively
     * @param {{[key: string]: string}} urls the URL prefixes from data-nd-urls; reads "device"
     * @returns {Function} the DataTables drawCallback function
     */
    groupDeviceRows: function (args, urls) {
      if (!args.nameKey)
        throw new Error('callback groupDeviceRows needs a "nameKey" naming the row key to use when dns is absent');
      const deviceUrl = urlFor(urls, 'device', 'groupDeviceRows');
      const label = function (row) {
        const name = row.dns || row[args.nameKey] || row.ip;
        let html = 'Device: <a href="' + deviceUrl + '?tab=details&q=' + enc(row.ip) + '">' + esc(name);
        if (row.dns || row[args.nameKey]) html += ' (' + esc(row.ip) + ') ';
        html += '</a> Model: ' + esc(row.model || '');
        html += esc(row.location ? ' Location: ' + row.location : '');
        return html;
      };
      return function () {
        const api = this.api();
        groupHeaders(api, args.colspan, function (group, getRow) {
          return label(getRow());
        });
        if (args.toggleOrder) bindGroupOrderToggle(api);
      };
    },

    /**
     * device/ports: rebinds the row-group collapse toggle and restores paging after every table build.
     * @returns {Function} the DataTables drawCallback function
     */
    portsCollapse: function () {
      return function () {
        const state = ndTables.collapse.disablePaging();
        document.querySelectorAll('.nd_row-collapser-toggle').forEach(function (el) {
          el.removeEventListener('click', ndTables.collapse.toggle);
          el.addEventListener('click', ndTables.collapse.toggle);
        });
        ndTables.collapse.pushFilter();
        ndTables.collapse.restorePage(state[0], state[1]);
      };
    }
  };

  /**
   * Resolves a column or callback spec (a bare name, or an object naming one under
   * "name") against the registry it belongs to, building the function DataTables calls.
   * kind and map name the registry being resolved against; otherMap and otherKind are
   * the other one, so a spec written for the wrong position (a callback named where a
   * column wants a renderer, or the reverse) throws naming the mistake rather than the
   * generic "no such name".
   * @param {{[key: string]: Function}} map the registry (RENDERERS or CALLBACKS) to resolve spec's name against
   * @param {string} kind the name of map's registry, used in the "no such name" error message
   * @param {{[key: string]: Function}} otherMap the other registry, checked to give a more specific error when spec names something there instead
   * @param {string} otherKind the name of otherMap's registry, used in that error message
   * @param {string | object} spec the column's or callback's data-nd-table entry: a bare name, or an object with "name" plus its args
   * @param {{[key: string]: string}} urls the URL prefixes from data-nd-urls, passed through to the resolved factory
   * @param {HTMLTableElement} table the table element, passed through to the resolved factory
   * @returns {Function} the function DataTables calls for this column or callback
   */
  function resolveFrom(map, kind, otherMap, otherKind, spec, urls, table) {
    const name = typeof spec === 'string' ? spec : spec.name;
    const factory = map[name];
    if (!factory) {
      if (otherMap[name]) throw new Error('netdisco-tables: "' + name + '" is a ' + otherKind + ', not a ' + kind);
      throw new Error('netdisco-tables: no ' + kind + ' named "' + name + '"');
    }
    // spec doubles as the args object, so its own dispatch key would
    // otherwise shadow a renderer argument also called "name" (deviceLabel's
    // dns/name/ip row-key convention).
    let args = spec;
    if (typeof spec !== 'string' && 'name' in spec) {
      args = {};
      Object.keys(spec).forEach(function (k) {
        if (k !== 'name') args[k] = spec[k];
      });
    }
    return factory(args, urls, table);
  }

  /**
   * Resolves a column's render spec against RENDERERS.
   * @param {string | object} spec the column's data-nd-table render entry: a bare name, or an object with "name" plus its args
   * @param {{[key: string]: string}} urls the URL prefixes from data-nd-urls
   * @param {HTMLTableElement} table the table element
   * @returns {Function} the render function DataTables calls for this column
   */
  function resolveRenderer(spec, urls, table) {
    return resolveFrom(RENDERERS, 'renderer', CALLBACKS, 'callback', spec, urls, table);
  }

  /**
   * Resolves a table's drawCallback or initComplete spec against CALLBACKS.
   * @param {string | object} spec the table's data-nd-table callback entry: a bare name, or an object with "name" plus its args
   * @param {{[key: string]: string}} urls the URL prefixes from data-nd-urls
   * @param {HTMLTableElement} table the table element
   * @returns {Function} the callback function DataTables calls
   */
  function resolveCallback(spec, urls, table) {
    return resolveFrom(CALLBACKS, 'callback', RENDERERS, 'renderer', spec, urls, table);
  }

  /**
   * Builds the DataTables options shared by every table, reading the page's own
   * data-nd-page-length and data-nd-length-menu body attributes for the paging defaults.
   * @param {HTMLTableElement} table the table element being built
   * @param {object} spec the table's parsed data-nd-table spec, consulted for customReport
   * @returns {object} the shared DataTables configuration object, before the table's own spec is applied over it
   */
  function defaults(table, spec) {
    const body = document.body.dataset;
    return {
      processing: true,
      stateSave: true,
      pageLength: Number(body.ndPageLength || 10),
      lengthMenu: JSON.parse(body.ndLengthMenu || '[10, 25, 50, 100]'),
      dom: '<"top"l<"nd_datatables-pager"p>f>rit<"bottom"><"clear">',
      // stated rather than left to the library, whose default changed to
      // full_numbers, adding first and last buttons netdisco never asked for
      pagingType: 'simple_numbers',
      language: {
        processing: 'Processing...',
        search: '_INPUT_',
        searchPlaceholder: 'Filter records...',
        lengthMenu: 'Show _MENU_ records.',
        info: '&nbsp;Showing _START_ to _END_ of _TOTAL_',
        infoFiltered: '(filtered from _MAX_ total)',
        infoEmpty: '&nbsp;No matching entries',
        paginate: { previous: '&larr; Previous', next: 'Next &rarr;' }
      },
      stateSaveParams: function (settings, data) {
        data.search.search = '';
        data.start = 0;
        if (spec.customReport) data.order = '';
      }
    };
  }

  /**
   * Builds one DataTable from a table element's data-nd-table and data-nd-urls
   * attributes, resolving each column's render spec and the table's drawCallback and
   * initComplete against the renderer and callback registries.
   * @param {HTMLTableElement} table the <table> element carrying data-nd-table (and optionally data-nd-urls, data-nd-data)
   * @param {Element} [root] the just-swapped htmx fragment root, if any, searched first
   *   for a data-nd-data JSON block before falling back to the whole document
   * @returns {DataTable} the constructed DataTables instance
   */
  function build(table, root) {
    const spec = JSON.parse(table.dataset.ndTable || '{}');
    const urls = JSON.parse(table.dataset.ndUrls || '{}');
    // "defaults":false opts a table out of every shared option, rather
    // than merging its own spec over them.
    const config = spec.defaults === false ? {} : defaults(table, spec);
    // Each spec key replaces its default wholesale, not merged one level
    // deep, so a fragment setting "language" drops every default string, not
    // just the ones it names. "customReport" and "defaults" are consumed
    // here rather than passed through: DataTables never sees either.
    Object.keys(spec).forEach(function (k) {
      if (k !== 'customReport' && k !== 'defaults') config[k] = spec[k];
    });
    (config.columns || []).forEach(function (col) {
      if (col.render) col.render = resolveRenderer(col.render, urls, table);
    });
    if (config.drawCallback) config.drawCallback = resolveCallback(config.drawCallback, urls, table);
    if (config.initComplete) config.initComplete = resolveCallback(config.initComplete, urls, table);
    if (table.dataset.ndData) {
      const id = table.dataset.ndData.replace(/^#/, '');
      // htmx swaps one tab pane at a time and never empties the pane it
      // leaves, so a stale sibling pane's own JSON block is still in the
      // document when this one is built. Look inside the just-swapped root
      // first; only a table built with no known root (a full page load)
      // reaches all the way out to the document.
      const block = (root && root.querySelector('#' + id)) || table.ownerDocument.getElementById(id);
      if (block) config.data = JSON.parse(block.textContent);
    }
    return new DataTable(table, config);
  }

  /**
   * Builds every not-yet-built table[data-nd-table] under root (or the whole document),
   * logging and skipping any table whose spec fails to build instead of letting one bad
   * table stop the rest.
   * @param {Element} [root] the just-swapped htmx fragment root, or the whole document when omitted
   * @returns {void}
   */
  function init(root) {
    const tables = (root || document).querySelectorAll('table[data-nd-table]');
    Array.prototype.forEach.call(tables, function (table) {
      if (table.classList.contains('dataTable')) return;
      // One bad data-nd-table (or data-nd-urls) degrades one table, not the
      // whole pane: a throw here would otherwise escape the htmx:after:swap
      // listener and leave holdUntilSettled never called.
      try {
        build(table, root);
      } catch (e) {
        console.error(e);
      }
    });
  }

  return {
    renderers: RENDERERS,
    callbacks: CALLBACKS,
    resolveRenderer: resolveRenderer,
    resolveCallback: resolveCallback,
    build: build,
    init: init,
    collapse: collapse
  };
})();
