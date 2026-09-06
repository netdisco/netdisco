// Every DataTable on the site is built here, from a data-nd-table attribute
// on the <table>, rather than by a script inside the fragment that delivered
// it. A fragment can then carry no JavaScript at all, which is what lets
// CodeQL see all of ours.
//
// JSON cannot carry a function, so a column's render and a table's
// drawCallback or initComplete are named here and referenced by name. Each
// entry is a factory: it takes the arguments the JSON gives it and the
// table's URL prefixes, and returns the function DataTables calls.

var ndTables = (function () {
  var esc = function (s) { return DataTable.util.escapeHtml(s == null ? '' : String(s)) };
  var enc = encodeURIComponent;
  var get = function (row, dotted) {
    return String(dotted).split('.').reduce(function (o, k) { return (o == null ? o : o[k]) }, row);
  };
  var link = function (href, text) { return '<a href="' + href + '">' + text + '</a>' };

  // DataTable.render.text() and .number() return an object keyed by render
  // type (display, filter, ...), falling back to the raw value for a type
  // they don't name, rather than a single function; this makes that shape
  // callable like every other entry in RENDERERS.
  var byType = function (spec) {
    return function (data, type) { return (spec[type] || function (d) { return d })(data) };
  };

  // Device label as netdisco shows it everywhere: dns, else name, else ip.
  // args.dns, args.name and args.ip name the row keys, each optional.
  var deviceLabel = function (args, row, fallback) {
    return get(row, args.dns || 'dns') || get(row, args.name || 'name') || get(row, args.ip || 'ip') || fallback;
  };
  var withQuery = function (base, q) { return base + (base.indexOf('?') === -1 ? '?' : '&') + q };

  // Every renderer needing a URL prefix reads it through here, so a fragment
  // missing a data-nd-urls key fails loudly, naming the key and the
  // renderer, instead of building an href with the literal text "undefined".
  var urlFor = function (urls, name, rendererName) {
    var url = urls[name];
    if (url == null) throw new Error('renderer ' + rendererName + ' needs data-nd-urls key "' + name + '"');
    return url;
  };

  var RENDERERS = {
    raw:        function () { return function (data) { return (data == null ? '' : data) } },
    escape:     function () { return byType(DataTable.render.text()) },
    number:     function () { return byType(DataTable.render.number(',', '.', 0)) },
    yesNo:      function () { return function (data) { return (data ? 'Yes' : 'No') } },
    dateTime:   function () { return DataTable.render.datetime('YYYY-MM-DD HH:mm') },
    capitalize: function () { return function (data) { var s = (data == null ? '' : String(data)); return esc(s.charAt(0).toUpperCase() + s.slice(1)) } },
    join:       function (args) {
      if (!args.key) throw new Error('renderer join needs a "key" naming the row array to join');
      return function (data, type, row) { return (get(row, args.key) || []).map(esc).join(args.with || '<br />') };
    },
    deviceName: function (args) { return function (data, type, row) { return esc(deviceLabel(args, row, data)) } },

    // Link to a device's ports tab. args.q and args.f each name a row key,
    // "data" meaning the cell itself: q for the device address, f for the
    // port. args.flags is a literal query suffix; args.descr adds a second
    // line from a row key; args.class sets the anchor's classes. Sorting and
    // filtering see the escaped value alone, unless args.always, which
    // renders the link for every type as the closures it replaces did.
    devicePortsLink: function (args, urls) {
      var portsUrl = urlFor(urls, 'device_ports', 'devicePortsLink');
      var rowKeyOrCell = function (row, rowKey, cellValue) { return (rowKey === 'data') ? cellValue : get(row, rowKey) };
      return function (data, type, row) {
        var text = esc(data);
        if (type !== 'display' && !args.always) return text;
        var deviceRowKey = args.q || 'ip';
        var portRowKey = args.f;
        var href = portsUrl + '&q=' + enc(rowKeyOrCell(row, deviceRowKey, data));
        if (portRowKey) href += '&f=' + enc(rowKeyOrCell(row, portRowKey, data));
        if (args.flags) href += '&' + args.flags;
        var cls = args.class ? ' class="' + args.class + '"' : '';
        var extra = args.descr ? '<br />' + esc(get(row, args.descr)) : '';
        return '<a' + cls + ' href="' + href + '">' + text + '</a>' + extra;
      };
    },

    // Link to a device's ports tab labelled with the device name rather than
    // the cell. args.q and args.f as above (f optional); args.suffix names a
    // row key shown in parentheses after the name; args.dns, args.name,
    // args.ip pick the label keys.
    devicePortsLinkNamed: function (args, urls) {
      var portsUrl = urlFor(urls, 'device_ports', 'devicePortsLinkNamed');
      return function (data, type, row) {
        var deviceRowKey = args.q;
        var portRowKey = args.f;
        var deviceAddress = (deviceRowKey === 'data' || !deviceRowKey) ? data : get(row, deviceRowKey);
        var href = portsUrl + '&q=' + enc(deviceAddress);
        if (portRowKey) href += '&f=' + enc(portRowKey === 'data' ? data : get(row, portRowKey));
        if (args.flags) href += '&' + args.flags;
        var text = esc(deviceLabel(args, row, data));
        if (args.suffix) text += (args.suffixSpace ? ' ' : '') + '(' + esc(get(row, args.suffix)) + ')';
        return link(href, text);
      };
    },

    // Link to the device page (uri_for('/device')), labelled with the device
    // name. args.tab adds a tab; args.suffix as above.
    deviceLink: function (args, urls) {
      var deviceUrl = urlFor(urls, 'device', 'deviceLink');
      return function (data, type, row) {
        var href = withQuery(deviceUrl, (args.tab ? 'tab=' + args.tab + '&' : '') + 'q=' + enc(data));
        var text = esc(deviceLabel(args, row, data));
        if (args.suffix) text += ' (' + esc(get(row, args.suffix)) + ')';
        return link(href, text);
      };
    },

    // Link to the device search. args.also repeats the value under a second
    // parameter name; args.label picks the label keys (dns, name, ip) or the
    // cell when absent; args.notSet is shown instead of a link when the cell
    // is empty.
    searchDeviceLink: function (args, urls) {
      var searchDeviceUrl = urlFor(urls, 'search_device', 'searchDeviceLink');
      return function (data, type, row) {
        if ((data == null || data === '') && args.notSet) return args.notSet;
        var href = searchDeviceUrl + '&q=' + enc(data) + (args.also ? '&' + args.also + '=' + enc(data) : '');
        var text = esc(args.label ? deviceLabel(args.label, row, data) : data);
        return link(href, text);
      };
    },

    // Link to the node search. args.upper shows the MAC upper-cased;
    // args.archived adds the archived flag and marker for an inactive row;
    // args.mark appends the marker inside the link without the flag;
    // args.domainPrefix prepends the NetBIOS domain; args.onlyIf names a row
    // key that must be truthy for the link to render at all (the cell is
    // shown plain otherwise).
    searchNodeLink: function (args, urls) {
      var searchNodeUrl = urlFor(urls, 'search_node', 'searchNodeLink');
      return function (data, type, row) {
        var shown = esc(args.upper ? String(data == null ? '' : data).toUpperCase() : data);
        if (type !== 'display' && !args.always) return shown;
        if (data == null || data === '') return shown;
        if (args.onlyIf && !get(row, args.onlyIf)) return shown;
        var flag = (args.archived && !row.active) ? '&archived=on' : '';
        var mark = ((args.archived || args.mark) && !row.active) ? (args.mark ? '&nbsp;&nbsp;<i class="fas fa-book text-warning"></i> ' : '&nbsp;<i class="fas fa-book text-warning"></i>&nbsp;') : '';
        var prefix = (args.domainPrefix && row.domain) ? esc('\\\\' + row.domain + '\\') : '';
        return prefix + link(searchNodeUrl + '&q=' + enc(data) + flag, shown + mark);
      };
    },

    // report/ipinventory ip column: a node link when the address belongs to a
    // known node, a device link when it was only seen on a device, plain text
    // when never seen.
    ipInventoryAddress: function (args, urls) {
      // Which URL is needed depends on the row, not the column, so each is
      // resolved only on the branch that actually uses it.
      return function (data, type, row) {
        var text = esc(data);
        if (type !== 'display' || !row.time_last) return text;
        if (row.node) {
          var flag = row.active ? '' : '&archived=on';
          var mark = row.active ? '' : '&nbsp;<i class="fas fa-book text-warning"></i>&nbsp;';
          return link(urlFor(urls, 'search_node', 'ipInventoryAddress') + '&q=' + enc(data) + flag, text + mark);
        }
        return link(urlFor(urls, 'search_device', 'ipInventoryAddress') + '&q=' + enc(data), text);
      };
    },

    // Link to a search tab with q set to the cell; args.list renders an array
    // of values as a comma separated list of links.
    searchLink: function (args, urls) {
      var searchUrl = urlFor(urls, 'search', 'searchLink');
      var one = function (v) { return link(withQuery(searchUrl, 'tab=' + args.tab + '&q=' + enc(v)), esc(v)) };
      return function (data) { return args.list ? (data || []).map(one).join(', ') : one(data) };
    },

    // Link to a report carrying one query parameter. args.report names the
    // URL in data-nd-urls, args.param the parameter; args.key takes the value
    // from a row key instead of the cell; args.show names a row key for the
    // label; args.blank is sent when the value is empty and args.blankText
    // shown; args.capitalize upper-cases the label's first letter.
    reportLink: function (args, urls) {
      var reportUrl = urlFor(urls, args.report, 'reportLink');
      return function (data, type, row) {
        var value = args.key ? get(row, args.key) : data;
        var empty = (value == null || value === '');
        var sent = empty ? (args.blank || 'blank') : value;
        var shown = args.show ? get(row, args.show) : value;
        var text = (shown == null || shown === '') ? (args.blankText || sent) : shown;
        text = String(text);
        if (args.capitalize) text = text.charAt(0).toUpperCase() + text.slice(1);
        return link(withQuery(reportUrl, args.param + '=' + enc(sent)), esc(text));
      };
    },

    // search/port ip column: address and port, with the device name beneath.
    searchPortLink: function (args, urls) {
      var portsUrl = urlFor(urls, 'device_ports', 'searchPortLink');
      return function (data, type, row) {
        var name = get(row, 'device.dns') || get(row, 'device.name');
        var below = name ? '<br>(' + esc(name) + ')' : '';
        return link(portsUrl + '&q=' + enc(data) + '&f=' + enc(row.port), esc(data) + ' [' + esc(row.port) + ']') + below;
      };
    },

    // The remaining one-offs, named after what they show.
    age: function (args) {
      return function (data, type, row) {
        if (type !== 'display') return get(row, args.stamp);
        return esc(data || 'Never').replace(/:00$/, ' mins').replace(':', ' hours ');
      };
    },
    powerPair:   function () { return function (data, type, row) { return (row.power2 ? esc(data) + ' / ' + esc(row.power2) : '') } },
    blankDomain: function () { return function (data) { return esc(data || '(Blank Domain)') } },
    nbUser:      function () { return function (data, type, row) { return esc(row.nbuser || '[No User]') } },
    portUpIcon:  function () {
      return function (data, type, row) {
        if (row.up_admin != 'up') return '<i class="fas fa-xmark"></i>';
        if (row.up != 'up' && row.up != 'dormant') return '<i class="fas fa-arrow-down text-danger"></i>';
        return '<i class="fas fa-angle-up text-success"></i>';
      };
    },
    // device/addresses subnet: admin viewers also get inventory and discover
    // shortcuts. Whether the viewer is admin arrives on the table.
    subnetLink: function (args, urls, table) {
      var admin = (table.dataset.ndAdmin === '1');
      // uri_base is only ever needed for the admin tool links, so it is only
      // required of data-nd-urls when this table's viewer is an admin.
      var uriBase = admin ? urlFor(urls, 'uri_base', 'subnetLink') : null;
      var searchDeviceUrl = urlFor(urls, 'search_device', 'subnetLink');
      return function (data) {
        var tools = admin
          ? '<a class="nd_stealth-link" href="' + uriBase + '/report/ipinventory?subnet=' + enc(data) + '"><i rel="tooltip" data-bs-placement="left" data-bs-title="Node Inventory" class="fas fa-laptop"></i></a> '
            + '<a class="nd_stealth-link nd_node-ext-link" href="' + uriBase + '/?device=' + enc(data) + '"><i rel="tooltip" data-bs-placement="left" data-bs-title="Discover Devices here" class="fas fa-magnifying-glass"></i></a>&nbsp;'
          : '';
        return tools + link(searchDeviceUrl + '&q=' + enc(data) + '&ip=' + enc(data), esc(data));
      };
    },
  };

  // toggle is bound with addEventListener rather than jQuery's .bind; $(this)
  // still resolves because the browser calls the handler with the clicked
  // element as its context either way.
  var collapse = {
    // temporarily disable datatables paging
    // returns [current_page_length, current_page_index]
    disablePaging: function () {
      $.fn.dataTable.ext.search.pop();
      var plen = $('#dp-data-table').DataTable().page.len();
      var pnum = $('#dp-data-table').DataTable().page();
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
      $.fn.dataTable.ext.search.push(
        function(settings, data, dataIndex) {
            var row = $($('#dp-data-table').DataTable().row(dataIndex).node());
            if (! row.data('collapsed-group')) { return true; }
            return row.attr('data-is-collapsed') == 'false';
        }
      );
    },

    // onclick handler
    // toggles visibility of a group of datatables rows
    // clicked element has the group name as data-collapsed-group
    toggle: function () {
      var groupname = $(this).data('collapsed-group');
      var [plen, pnum] = ndTables.collapse.disablePaging();

      // groupname is not in a class selector due to port name characters
      $('tr.nd_collapsible').each(function(index) {
          if ($(this).data('collapsed-group') == groupname) {
              if ($(this).attr('data-is-collapsed') == 'true') {
                $(this).attr('data-is-collapsed', 'false');
              }
              else {
                $(this).attr('data-is-collapsed', 'true');
              }
          }
      });

      ndTables.collapse.pushFilter();
      ndTables.collapse.restorePage(plen, pnum);

      var icon = $(this).find('i');
      icon.toggleClass(
        "fa-list-ol fa-arrow-up-wide-short fa-rotate-180"
      );
    },
  };

  var CALLBACKS = {
    // Repeats of the first column become one group header row above their
    // first occurrence. args.colspan is the visible column count. The group
    // value is escaped by default, matching a data-nd-data JSON row (raw
    // text); args.html true skips escaping for a DOM-sourced table, whose
    // cells DataTables reads as already-rendered HTML.
    groupRows: function (args) {
      var renderGroup = args.html ? function (v) { return v } : esc;
      return function () {
        var api = this.api();
        var rows = api.rows({ page: 'current' }).nodes();
        var last = null;
        api.column(0, { page: 'current' }).data().each(function (group, i) {
          if (last !== group) {
            rows[i].insertAdjacentHTML('beforebegin',
              '<tr class="group"><td colspan="' + args.colspan + '">' + renderGroup(group) + '</td></tr>');
            last = group;
          }
        });
      };
    },

    // device/ports: rebinds the row-group collapse and restores paging after
    // every build. Was the tail of the ports fragment's script.
    portsCollapse: function () {
      return function () {
        var state = ndTables.collapse.disablePaging();
        document.querySelectorAll('.nd_row-collapser-toggle').forEach(function (el) {
          el.removeEventListener('click', ndTables.collapse.toggle);
          el.addEventListener('click', ndTables.collapse.toggle);
        });
        ndTables.collapse.pushFilter();
        ndTables.collapse.restorePage(state[0], state[1]);
      };
    },
  };

  function resolve(spec, urls, table) {
    var name = (typeof spec === 'string') ? spec : spec.name;
    var args = (typeof spec === 'string') ? {} : spec;
    var factory = RENDERERS[name] || CALLBACKS[name];
    if (!factory) throw new Error('netdisco-tables: no renderer or callback named "' + name + '"');
    return factory(args, urls, table);
  }

  function defaults(table, spec) {
    var body = document.body.dataset;
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
        paginate: { previous: '&larr; Previous', next: 'Next &rarr;' },
      },
      stateSaveParams: function (settings, data) {
        data.search.search = '';
        data.start = 0;
        if (spec.customReport) data.order = '';
      },
    };
  }

  function build(table) {
    var spec = JSON.parse(table.dataset.ndTable || '{}');
    var urls = JSON.parse(table.dataset.ndUrls || '{}');
    // "defaults":false opts a table out of every shared option, for a table
    // whose old script never included datatabledefaults.tt either.
    var config = (spec.defaults === false) ? {} : defaults(table, spec);
    // Each spec key replaces its default wholesale, not merged one level
    // deep, so a fragment setting "language" drops every default string, not
    // just the ones it names. "customReport" and "defaults" are consumed
    // here rather than passed through: DataTables never sees either.
    Object.keys(spec).forEach(function (k) { if (k !== 'customReport' && k !== 'defaults') config[k] = spec[k] });
    (config.columns || []).forEach(function (col) {
      if (col.render) col.render = resolve(col.render, urls, table);
    });
    if (config.drawCallback) config.drawCallback = resolve(config.drawCallback, urls, table);
    if (config.initComplete) config.initComplete = resolve(config.initComplete, urls, table);
    if (table.dataset.ndData) {
      var block = table.ownerDocument.getElementById(table.dataset.ndData.replace(/^#/, ''));
      if (block) config.data = JSON.parse(block.textContent);
    }
    return new DataTable(table, config);
  }

  function init(root) {
    var tables = (root || document).querySelectorAll('table[data-nd-table]');
    Array.prototype.forEach.call(tables, function (table) {
      if (table.classList.contains('dataTable')) return;
      // One bad data-nd-table (or data-nd-urls) degrades one table, not the
      // whole pane: a throw here would otherwise escape the htmx:afterSwap
      // listener and leave holdUntilSettled never called.
      try { build(table) } catch (e) { console.error(e) }
    });
  }

  return { renderers: RENDERERS, callbacks: CALLBACKS, resolve: resolve, build: build, init: init, collapse: collapse };
})();
