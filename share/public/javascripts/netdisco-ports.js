// The Ports tab's table, drawn from JSON by the loader that ajax/device/ports.tt
// names, so DataTables draws only the rows on screen.
//
// A cell's markup is the old ports.tt's, attribute for attribute: port control,
// netdisco.js and the CSS find what they act on through its classes, data-*
// attributes and the order of its icons. A plugin column with a template
// arrives drawn by the server; without one it is drawn from its field, or by a
// renderer a plugin registers with registerColumn().

const ndPorts = (function () {
  'use strict';

  const esc = function (s) {
    return DataTable.util.escapeHtml(s == null ? '' : String(s));
  };
  const enc = function (s) {
    return encodeURIComponent(s == null ? '' : String(s));
  };
  const ucfirst = function (s) {
    s = s == null ? '' : String(s);
    return s.charAt(0).toUpperCase() + s.slice(1);
  };
  const tip = function (title) {
    return ' rel="tooltip" data-bs-placement="top" data-bs-animation="false" data-bs-title="' + title + '"';
  };
  const strip = function (html) {
    return DataTable.util
      .stripHtml(html == null ? '' : String(html))
      .replace(/\s+/g, ' ')
      .trim();
  };
  const has = function (o, k) {
    return Object.prototype.hasOwnProperty.call(o, k);
  };

  const SHOW = 'Show <div class="nd_arrow-up-down-left-down fas fa-square-plus"></div>&nbsp;';
  const ARCHIVED = '<i class="fas fa-book nd_icon-archived" title="Archived node (inactive)"></i>&nbsp; ';
  const FREE = '<i class="fas fa-circle-arrow-down text-success fa-lg" title="Port free (no active nodes)"></i>';
  const SPINNER = '<span><i class="fas fa-spinner fa-spin"></i> Waiting for results...</span>';

  /**
   * What a cell is drawn from besides its row: the URL prefixes from the
   * table's data-nd-urls, and the meta block the data route sent (the
   * request's options, the thresholds, the device, the VLAN names).
   * @typedef {object} PortsContext
   * @property {{[key: string]: string}} urls
   * @property {any} meta
   */

  // a count of things over a threshold, with the toggle netdisco.js binds
  const collapsed = function (label, inner, boxClass) {
    return (
      '<div class="nd_nodes-total">' +
      label +
      ' <span class="nd_collapse-vlans">' +
      SHOW +
      '</span></div><div class="nd_collapsing nd_collapse-pre-hidden' +
      (boxClass ? ' ' + boxClass : '') +
      '">' +
      inner +
      '</div>'
    );
  };

  const portsLink = function (c, q, port, cls, inner) {
    return (
      '<a' +
      (cls ? ' class="' + cls + '"' : '') +
      ' href="' +
      esc(c.urls.device_ports + '&q=' + enc(q) + (port == null ? '' : '&f=' + enc(port) + '&prefer=port')) +
      '">' +
      inner +
      '</a>'
    );
  };
  const nodeLink = function (c, q, inner, attrs) {
    return '<a href="' + esc(c.urls.search_node + '&q=' + enc(q)) + '"' + (attrs || '') + '>' + inner + '</a>';
  };

  /**
   * The connected nodes of one port, as ajax/device/port_nodes.tt drew them.
   * The node carrying the neighbor's own address is skipped but still counts
   * as first or last, as it did there.
   * @param {any} r the port's row
   * @param {any[]} nodes the port's nodes
   * @param {PortsContext} c the table's context
   * @returns {string} the markup
   */
  const nodesHtml = function (r, nodes, c) {
    const p = c.meta.params;
    const ipLimit = Number(c.meta.settings.devport_ips_collapse_threshold);
    let h = '';
    nodes.forEach(function (n, i) {
      if (n.neighbor) return;
      h += '<div class="nd_div-closer' + (i === nodes.length - 1 ? ' nd_div-closer-last' : '') + '">';
      if (r.remote_ip || r.is_uplink || i > 0) h += '<br/>';
      if (n.archived) h += ARCHIVED;
      h += '<i class="fas fa-laptop" title="Client"></i>&nbsp; ' + nodeLink(c, n.mac, esc(n.mac));
      if (Number(n.vlan) > 0 && String(n.vlan) !== String(r.vlan == null ? '' : r.vlan)) {
        h += ' (on vlan ' + esc(n.vlan) + ')';
      }
      if (p.n_ssid && n.ssids && n.ssids.length) {
        h +=
          ' (SSID: ' +
          n.ssids
            .map(function (s) {
              return '<a href="' + esc(c.urls.portssid + '?ssid=' + enc(s)) + '">' + esc(s) + '</a>';
            })
            .join(' ') +
          ')';
      }
      if (p.n_vendor && n.vendor != null) {
        h += ' (<a href="' + esc(c.urls.nodevendor + '?vendor=' + enc(n.vendor)) + '">' + esc(n.vendor) + '</a>)';
      }
      if (p.n_age) h += esc(' (' + (n.age == null ? '' : n.age) + ')');
      if (p.n_ip4 || p.n_ip6) {
        const ips = n.ips || [];
        const over = ips.length > ipLimit;
        let list = '';
        ips.forEach(function (ip, j) {
          list += j === 0 && over ? ' &nbsp;' : ' <br/>&nbsp;';
          if (ip.archived) list += ARCHIVED;
          list += ' ';
          if (ip.dns) {
            if (p.n_dns) {
              list +=
                nodeLink(c, ip.dns, esc(ip.dns), ' title="' + esc(ip.ip) + '"') +
                ' ' +
                nodeLink(c, ip.ip, '(' + esc(ip.ip) + ')', ' title="' + esc(ip.dns) + '"');
            } else {
              list += nodeLink(c, ip.ip, esc(ip.dns), ' title="' + esc(ip.ip) + '"');
            }
          } else {
            list += nodeLink(c, ip.ip, esc(ip.ip));
          }
        });
        h += over ? ' ' + collapsed('&nbsp;&nbsp;<strong>' + ips.length + ' IPs</strong>', list) : list;
      }
      h += '</div>';
      if (p.n_netbios && n.netbios) {
        n.netbios.forEach(function (nbt, k) {
          if (k > 0) h += '<br/>';
          h +=
            ' &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;\\\\<a href="' +
            esc(c.urls.netbios + '?domain=' + enc(nbt.domain)) +
            '" title="Nodes in this Domain">' +
            esc(nbt.domain) +
            '</a>\\' +
            nodeLink(c, nbt.nbname, esc(nbt.nbname)) +
            ' <br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;' +
            esc(nbt.nbuser || '[No User]') +
            '@' +
            nodeLink(c, nbt.ip, esc(nbt.ip));
        });
      }
    });
    return h;
  };

  // the neighbor part of the connected nodes and devices cell
  const neighborHtml = function (r, c) {
    const p = c.meta.params;
    const mac = r.neighbor_mac ? ' ' + nodeLink(c, r.neighbor_mac, esc(r.neighbor_mac), ' class="text-muted"') : '';
    const kind = r.remote_is_phone
      ? ' <i class="fas fa-phone" title="VoIP Phone"></i>&nbsp;'
      : r.remote_is_wap
        ? ' <i class="fas fa-rss" title="Wireless Access Point"></i>&nbsp;'
        : '';
    const inventory = p.n_inventory && r.remote_inventory ? ' ' + esc(r.remote_inventory) + '<br/>' : '';
    let h;
    if (r.neighbor_ip) {
      h =
        '<i class="fas fa-link' +
        (r.manual_topo ? ' text-warning' : '') +
        '" title="' +
        (r.manual_topo ? 'Manually configured topology link' : 'Discovered neighbor') +
        '"></i>' +
        kind +
        ' ' +
        portsLink(c, r.neighbor_ip, null, '', esc(r.neighbor_dns || r.neighbor_ip));
      if (r.remote_port) h += ' - ' + portsLink(c, r.neighbor_ip, r.remote_port, '', esc(r.remote_port));
      h += mac + ' <br/>' + inventory;
      if (p.n_detailed_inventory) {
        h +=
          ' (' +
          esc(
            (r.remote_ip ? 'IP: ' + r.remote_ip : '') +
              (r.remote_id ? ' id: ' + r.remote_id : '') +
              (r.remote_type ? ' type: ' + r.remote_type : '')
          ) +
          ')<br/>';
      }
    } else if (r.remote_ip) {
      const discoverable = r.remote_is_discoverable;
      h =
        '<i class="fas ' +
        (discoverable ? 'fa-link-slash' : 'fa-eye-slash') +
        ' text-danger" title="' +
        (discoverable ? 'Neighbor not yet discovered' : 'Not discoverable (WAP/phone discovery disabled)') +
        '"></i>&nbsp;' +
        kind +
        ' ' +
        nodeLink(c, r.remote_ip, esc(r.remote_dns || r.remote_ip));
      if (r.remote_port && !(r.remote_is_wap || r.remote_is_phone)) h += ' - ' + esc(r.remote_port);
      if ((r.remote_is_wap || r.remote_is_phone) && r.remote_type) {
        h += ' <span class="text-muted">' + esc(r.remote_type) + '</span>';
      }
      h += mac + ' <br/>' + inventory;
      if (p.n_detailed_inventory && (r.remote_id || r.remote_type)) {
        h +=
          ' (' +
          esc((r.remote_id ? 'id: ' + r.remote_id : '') + (r.remote_type ? ' type: ' + r.remote_type : '')) +
          ')<br/>';
      }
    } else {
      h =
        '<i class="fas fa-link-slash text-danger" title="Possible uplink: neighbor seen but no IP recorded"></i>&nbsp; (possible uplink)';
    }
    return h;
  };

  // the content of a cell whose value can be edited under Port Control
  const editable = function (value, canEdit) {
    return (
      (canEdit ? '<i class="far fa-pen-to-square nd_edit-icon"></i> ' : '') +
      '<div class="nd_editable-cell-content">' +
      esc(value) +
      '</div>'
    );
  };
  const editableAttrs = function (r, c, field, canEdit) {
    if (!canEdit) return { nowrap: '', class: 'nd_editable-cell' };
    return {
      nowrap: '',
      class: 'nd_editable-cell',
      contenteditable: 'true',
      'data-field': field,
      'data-for-device': c.meta.device,
      'data-for-port': r.port
    };
  };

  // a column that shows one field of the row as it is
  const field = function (key, extra) {
    return Object.assign(
      {
        html: function (r) {
          return esc(r[key]);
        },
        value: function (r) {
          return r[key] == null ? '' : r[key];
        }
      },
      extra
    );
  };
  const NOWRAP = {
    attrs: function () {
      return { nowrap: '' };
    }
  };
  const NUMERIC = { type: 'num' };

  // Template Toolkit's uri filter, which the server's links were given their
  // values through: encodeURIComponent leaves !*'() alone, which it does not
  const ttUri = function (s) {
    return enc(s).replace(/[!*'()]/g, function (ch) {
      return '%' + ch.charCodeAt(0).toString(16).toUpperCase();
    });
  };

  /**
   * Each built-in column. html draws the cell, attrs gives the td's own
   * attributes, and value is what the column sorts and, unless it has a
   * filter of its own, filters on. A column without a value sorts on the text
   * it draws, as the old DOM table did. type is the DataTables column type
   * where it is not text.
   */
  const COLUMNS = {
    status: {
      html: function (r, c) {
        let h;
        if (r.up_admin !== 'up') {
          h = '<i class="fas fa-xmark fa-lg" title="Port disabled (admin down)"></i>';
        } else if (r.up === 'up' && r.stp === 'blocking' && (r.vlan_count || 0) < 2) {
          h = '<i class="fas fa-ban text-info fa-lg" title="STP blocking"></i>';
        } else if (r.error_disable_cause) {
          h =
            '<i class="fas fa-circle-exclamation text-danger fa-lg" title="Error disabled: ' +
            esc(r.error_disable_cause) +
            '"></i>';
        } else if (r.is_free) {
          h = FREE;
        } else if (r.up !== 'up' && r.up !== 'dormant') {
          h = c.meta.only_free ? FREE : '<i class="fas fa-arrow-down text-danger fa-lg" title="Port down (link lost)"></i>';
        } else {
          h = '<i class="fas fa-angle-up text-success fa-lg" title="Port up"></i>';
        }
        if (r.slave_of) {
          h += '<br/> ';
          if (r.agg_master_up_admin !== 'up') {
            h += '<small><i class="fas fa-users text-muted" title="LAG member: aggregate disabled"></i></small>';
          } else if (r.agg_master_up === 'up') {
            h += '<small><i class="fas fa-users text-success" title="LAG member: aggregate up"></i></small>';
          } else {
            h += '<small><i class="fas fa-users text-danger" title="LAG member: aggregate down"></i></small>';
          }
        }
        return h;
      },
      value: function () {
        return '';
      },
      attrs: function () {
        return { class: 'nd_center-cell nd_devport-icon' };
      }
    },

    c_port: {
      type: 'portsort',
      html: function (r, c) {
        const p = c.meta.params;
        let h =
          '<a class="nd_log-icon" href="' +
          esc(c.urls.portlog + '?q=' + enc(c.meta.device) + '&f=' + enc(r.port)) +
          '"> <i class="far fa-file-lines"' +
          tip('View Port Log') +
          '></i> </a>';
        if (r.has_group) {
          // as toggleGroup last left it, once the table is drawn again
          const folded =
            r._groupFolded !== undefined
              ? r._groupFolded
              : (p.p_fold_dotzero && r.only_dot_zero) || p.p_fold_subinterfaces;
          h +=
            ' <span class="nd_log-icon nd_row-collapser-toggle" data-collapsed-group="' +
            esc(r.port) +
            '"> <i class="fas ' +
            (folded ? 'fa-list-ol' : 'fa-arrow-up-wide-short fa-rotate-180') +
            '"' +
            tip('Toggle Subinterfaces') +
            '></i> </span>';
        }
        if (p.c_admin && r.acl_service) {
          const up = r.up_admin === 'up';
          h +=
            ' <span class="nd_hand-icon"> <i class="fas fa-bullseye" data-action="bounce"' +
            (up ? '' : ' style="display: none"') +
            tip('Bounce Port') +
            '></i> <i class="fas ' +
            (up ? 'fa-hand-point-down' : 'fa-hand-point-up') +
            '"' +
            tip(up ? 'Disable Port' : 'Enable Port') +
            '></i> </span>';
        }
        h +=
          ' ' +
          portsLink(
            c,
            c.meta.q,
            r.port,
            'nd_this-port-only nd_port-only-first',
            (r.is_master || r.has_subinterfaces ? ' <small><i class="fas fa-users text-muted"></i></small>&nbsp;' : '') +
              esc(r.port)
          );
        if (r.slave_of) {
          h += '<br/> ' + portsLink(c, c.meta.q, r.slave_of, 'nd_this-port-only', esc(r.slave_of));
        }
        return h;
      },
      value: function (r) {
        return r.port;
      },
      attrs: function (r, c) {
        if (!(c.meta.params.c_admin && r.acl_service)) return { nowrap: '' };
        return {
          nowrap: '',
          class: 'nd_editable-cell',
          'data-action': r.up_admin === 'up' ? 'down' : 'up',
          'data-field': 'c_port',
          'data-for-device': c.meta.device,
          'data-for-port': r.port
        };
      }
    },

    c_descr: field('descr', Object.assign({ type: 'portsort' }, NOWRAP)),
    c_comment: field('comment', NOWRAP),
    c_type: field('type'),
    c_ifindex: field('ifindex', NUMERIC),
    c_lastchange: field('lastchange_stamp'),

    c_name: {
      type: 'portsort',
      html: function (r, c) {
        return editable(r.name, c.meta.params.c_admin && r.acl_name);
      },
      value: function (r) {
        return r.name == null ? '' : r.name;
      },
      attrs: function (r, c) {
        return editableAttrs(r, c, 'c_name', c.meta.params.c_admin && r.acl_name);
      }
    },

    c_tags: {
      html: function (r) {
        return (r.tags || [])
          .map(function (t) {
            return '<span class="badge text-bg-success">' + esc(t) + '</span>';
          })
          .join(' ');
      },
      value: function (r) {
        return (r.tags || []).join(' ');
      }
    },

    // The links a site configures. The ones whose url is only the variables
    // below are in meta.links and drawn here; any other kind needs Template
    // Toolkit, and then the server draws the column (externallinks.tt).
    c_links: {
      html: function (r, c) {
        const links = c.meta.links;
        if (!links) return (r.cells && r.cells.c_links) || '';
        const off = r.links_off || [];
        const vars = Object.assign({}, c.meta.link_vars, {
          port: ttUri(r.port),
          mac: ttUri(r.mac),
          ifindex: ttUri(r.ifindex)
        });
        return links
          .map(function (link, i) {
            if (off.indexOf(i) !== -1) return '';
            const url = String(link.url).replace(/\[%\s*(\w+)\s*%\]/g, function (m, name) {
              return has(vars, name) ? vars[name] : '';
            });
            return (
              '<a href="' +
              esc(url) +
              '" target="_blank"><span class="badge text-bg-secondary"><i class="fas fa-up-right-from-square"></i> ' +
              esc(link.displayname) +
              '</span></a>'
            );
          })
          .join(' ');
      },
      value: function (r, c) {
        return strip(COLUMNS.c_links.html(r, c));
      }
    },

    c_speed_admin: field('speed_admin'),
    c_speed: field('speed'),
    c_duplex_admin: {
      html: function (r) {
        return esc(ucfirst(r.duplex_admin));
      },
      value: function (r) {
        return ucfirst(r.duplex_admin);
      }
    },
    c_duplex: {
      html: function (r) {
        return esc(ucfirst(r.duplex));
      },
      value: function (r) {
        return ucfirst(r.duplex);
      }
    },
    c_error: field('error_disable_cause'),
    c_mac: field('mac'),
    c_mtu: field('mtu', NUMERIC),

    c_pvid: {
      type: 'num',
      html: function (r, c) {
        const p = c.meta.params;
        const shown = Number(r.vlan) > 0;
        if (p.c_admin && r.acl_pvid) return editable(shown ? r.vlan : '', true);
        if (!shown) return '';
        const label = p.p_vlan_names ? r.native_vlan_name : r.vlan;
        return '<a class="nd_linkcell" href="' + esc(c.urls.search + '?tab=vlan&q=' + enc(label)) + '">' + esc(label) + '</a>';
      },
      value: function (r, c) {
        if (r.vlan == null || Number(r.vlan) <= 0) return '';
        return c.meta.params.p_vlan_names ? r.native_vlan_name : r.vlan;
      },
      attrs: function (r, c) {
        if (!(c.meta.params.c_admin && r.acl_pvid)) return {};
        return {
          class: 'nd_editable-cell',
          contenteditable: 'true',
          'data-default': r.vlan == null ? '' : r.vlan,
          'data-field': 'c_pvid',
          'data-for-device': c.meta.device,
          'data-for-port': r.port
        };
      }
    },

    c_vmember: {
      html: function (r, c) {
        const count = r.vlan_count || 0;
        if (!count) return '';
        if (count > Number(c.meta.settings.devport_vlan_limit)) {
          return '<i class="fas fa-asterisk text-warning"></i> (' + count + ' is too many to list)';
        }
        const names = c.meta.params.p_vlan_names ? c.meta.vlan_names : null;
        const list = (r.vlans || [])
          .map(function (v) {
            const label = names && names[v] != null ? names[v] : v;
            return '<a href="' + esc(c.urls.search + '?tab=vlan&q=' + enc(label)) + '">' + esc(label) + '</a>';
          })
          .join(', ');
        if (count > Number(c.meta.settings.devport_vlans_collapse_threshold)) {
          return collapsed('<strong>' + count + ' VLANs</strong>', list);
        }
        return list;
      }
    },

    c_power: {
      html: function (r, c) {
        const power = r.power;
        if (!power) return '';
        const admin = c.meta.params.c_admin && r.acl_service;
        if (power.admin === 'true') {
          return (
            (admin
              ? '<i class="fas fa-power-off nd_power-icon nd_power-on"' + tip('Disable Power') + '></i>'
              : '<i class="fas fa-power-off nd_power-on"></i>') +
            ' <span>' +
            (power.power && power.power > 0 ? esc(power.power) + '&nbsp;mW' : '(' + esc(power.status) + ')') +
            '</span>'
          );
        }
        return admin
          ? '<i class="fas fa-power-off nd_power-icon"' + tip('Enable Power') + '></i>'
          : '<i class="fas fa-power-off"></i>';
      },
      attrs: function (r, c) {
        const power = r.power;
        if (!power) return {};
        const on = power.admin === 'true';
        if (c.meta.params.c_admin && r.acl_service) {
          return {
            nowrap: '',
            'data-action': on ? 'false' : 'true',
            'data-field': 'c_power',
            'data-for-device': c.meta.device,
            'data-for-port': r.port
          };
        }
        return on ? { nowrap: '' } : {};
      }
    },

    c_ssid: {
      html: function (r) {
        return (r.ssids || []).map(esc).join(', ');
      },
      value: function (r) {
        return (r.ssids || []).join(', ');
      }
    },

    c_nac_summary: {
      html: function (r, c) {
        const nac = r.nac;
        if (r.up !== 'up' || !nac) return '';
        const user = nac.user == null ? '' : nac.user;
        return (
          '<i class="fas ' +
          (nac.port_status === 'authorized' ? 'fa-circle-check' : 'fa-ban') +
          '"' +
          tip(esc(nac.port_status || 'unknown')) +
          '></i> <i class="fas ' +
          (nac.state === 'authenticated' ? 'fa-link' : 'fa-link-slash') +
          '"' +
          tip(esc(nac.state || 'unknown')) +
          '></i> <i class="fas ' +
          (nac.mab ? 'fa-laptop' : 'fa-user') +
          '" title="' +
          (nac.mab ? 'MAC Authentication Bypass (MAB)' : '802.1X user authentication') +
          '"></i> ' +
          nodeLink(c, user, esc(user))
        );
      }
    },

    // The nodes and the neighbor share one cell, whichever of the two columns
    // is on; the header names only one of them.
    c_neighbors: {
      html: function (r, c) {
        const p = c.meta.params;
        let h = '';
        if (p.c_neighbors && (r.remote_ip || r.is_uplink)) h += neighborHtml(r, c);
        if (p.c_nodes) {
          if ((r.node_count || 0) > Number(c.meta.settings.devport_nodes_collapse_threshold)) {
            // filled from the server when first opened, see loadNodes
            h +=
              ' <div class="nd_nodes-total"><strong>' +
              r.node_count +
              ' nodes</strong> <span class="nd_collapse-vlans">' +
              SHOW +
              '</span></div><div class="nd_collapsing nd_collapse-pre-hidden nd_nodes-fetch">' +
              SPINNER +
              '</div>';
          } else {
            h += nodesHtml(r, r.nodes || [], c);
          }
        }
        if (p.c_admin && c.meta.settings.portctl_topology && r.acl_service) {
          h +=
            ' <a class="nd_log-icon" href="' +
            esc(c.urls.topology + '?dev1=' + enc(c.meta.device) + '&port1=' + enc(r.port)) +
            '"><i class="fas fa-link text-warning"' +
            tip('Manual Topology') +
            '></i></a>';
        }
        return h;
      },
      // The search text carries every node's text whether or not its markup
      // is drawn, and the neighbor's own fields; without c_nodes the column
      // filters on what it shows.
      filter: function (r, c) {
        return c.meta.params.c_nodes ? r.search || '' : null;
      }
    },

    c_stp: field('stp'),
    c_up: {
      html: function (r) {
        return esc(ucfirst(r.up_admin)) + ' / ' + esc(ucfirst(r.up));
      },
      value: function (r) {
        return ucfirst(r.up_admin) + ' / ' + ucfirst(r.up);
      }
    }
  };
  COLUMNS.c_nodes = COLUMNS.c_neighbors;

  // Renderers a plugin registers for its own column, by the name its
  // register_device_port_column gives as "renderer".
  const REGISTERED = {};

  /**
   * A plugin or custom field column: the markup the server drew where the
   * column has a template of its own, otherwise its field, editable under
   * Port Control where the column says it may be. A cell the column's ACL
   * hides is sent without its value and drawn empty.
   * @param {string} name the column's name
   * @param {PortsContext} c the table's context
   * @returns {any} the column, as in COLUMNS
   */
  const extraColumn = function (name, c) {
    const config = (c.meta.extra || {})[name] || {};
    const registered = config.renderer && has(REGISTERED, config.renderer) ? REGISTERED[config.renderer] : null;
    const hidden = function (r) {
      return Boolean(r.hidden_cells && r.hidden_cells[name]);
    };
    const drawn = function (r) {
      return Boolean(r.cells && has(r.cells, name));
    };
    const canEdit = function (r, cx) {
      return cx.meta.params.c_admin && config.editable && r.acl_name;
    };
    return {
      html: function (r, cx) {
        if (hidden(r)) return '';
        if (registered) return registered.html(r, cx);
        if (drawn(r)) return r.cells[name];
        return editable((r.fields || {})[config.field], canEdit(r, cx));
      },
      value: function (r, cx) {
        if (hidden(r)) return '';
        if (registered && registered.value) return registered.value(r, cx);
        if (registered || drawn(r)) return null;
        const v = (r.fields || {})[config.field];
        return v == null ? '' : v;
      },
      filter: registered && registered.filter,
      attrs: function (r, cx) {
        if (hidden(r)) return {};
        if (registered) return registered.attrs ? registered.attrs(r, cx) : {};
        if (drawn(r)) return {};
        return editableAttrs(r, cx, config.field, canEdit(r, cx));
      }
    };
  };

  /**
   * A built-in column, or a plugin or custom field one, which the data route
   * lists in meta.extra. A name that is neither is an error, not an empty cell.
   * @param {string} name a column's name
   * @param {PortsContext} c the table's context
   * @returns {any} the column, as in COLUMNS
   */
  const columnFor = function (name, c) {
    if (has(COLUMNS, name)) return COLUMNS[name];
    if (has(c.meta.extra || {}, name)) return extraColumn(name, c);
    throw new Error('netdisco-ports: no column named "' + name + '"');
  };

  // one value per row and column, for the columns that sort and filter on
  // the text they draw: working it out three times a cell is the cost
  const memo = function (row, key, make) {
    const m = row._m || (row._m = {});
    return has(m, key) ? m[key] : (m[key] = make());
  };

  /**
   * The DataTables column for one of the table's: render answers display
   * with the cell's markup, filter with its text and everything else, which
   * is sorting, with its value.
   * @param {string} name the column's name
   * @param {PortsContext} c the table's context
   * @param {boolean} [first] whether this is the status column, which neither sorts nor filters
   * @returns {object} the DataTables column options
   */
  const dataTableColumn = function (name, c, first) {
    const column = columnFor(name, c);
    const text = function (r) {
      return memo(r, name, function () {
        return strip(column.html(r, c));
      });
    };
    const col = {
      data: null,
      type: column.type || 'string',
      render: function (data, type, r) {
        if (type === 'display') return column.html(r, c);
        if (type === 'filter') {
          const f = column.filter ? column.filter(r, c) : null;
          if (f != null) return f;
          const v = column.value ? column.value(r, c) : null;
          return v != null ? String(v) : text(r);
        }
        const v = column.value ? column.value(r, c) : null;
        return v != null ? v : text(r);
      },
      createdCell: function (td, cellData, r) {
        if (!column.attrs) return;
        const attrs = column.attrs(r, c);
        Object.keys(attrs).forEach(function (k) {
          if (k === 'class') td.classList.add.apply(td.classList, attrs[k].split(' '));
          else td.setAttribute(k, attrs[k] == null ? '' : String(attrs[k]));
        });
      }
    };
    if (first) {
      col.orderable = false;
      col.searchable = false;
    }
    return col;
  };

  // whether a row starts folded under its parent port
  const startsFolded = function (r, p) {
    return Boolean(r.group && ((p.p_fold_dotzero && r.is_dot_zero) || p.p_fold_subinterfaces));
  };

  // Flips every row of a group between folded and shown, and the toggle's
  // own icon. A row not drawn yet only changes in its data, which is where
  // the table's own filter reads it from. The parent port keeps the state for
  // its icon, should the table be drawn again with other columns.
  const toggleGroup = function (api, toggle) {
    const group = toggle.getAttribute('data-collapsed-group');
    let parent = null;
    let folded = null;
    api.rows().every(function () {
      const row = this.data();
      if (row.port === group) parent = row;
      if (row.group !== group) return;
      row._folded = !row._folded;
      folded = row._folded;
      const tr = this.node();
      if (tr) tr.setAttribute('data-is-collapsed', row._folded ? 'true' : 'false');
    });
    if (parent && folded !== null) parent._groupFolded = folded;
    const icon = toggle.querySelector('i');
    if (icon) {
      icon.classList.toggle('fa-list-ol');
      icon.classList.toggle('fa-arrow-up-wide-short');
      icon.classList.toggle('fa-rotate-180');
    }
    api.draw(false);
  };

  /**
   * Fetches and draws the nodes of a port over the collapse threshold, the
   * first time its list is opened, or again after a failure.
   * @param {any} api the DataTables API of the table
   * @param {Element} box the .nd_nodes-fetch element to fill
   * @param {PortsContext} c the table's context
   * @returns {void}
   */
  const loadNodes = function (api, box, c) {
    if (box.classList.contains('nd_loading') || box.classList.contains('nd_loaded')) return;
    const tr = box.closest('tr');
    const row = tr && api.row(tr).data();
    if (!row) return;
    box.classList.add('nd_loading');
    // every part is a literal, none of it is data
    // eslint-disable-next-line no-unsanitized/property
    box.innerHTML = SPINNER;
    const url = c.urls.port_nodes + '?q=' + enc(c.meta.device) + '&port=' + enc(row.port) + (c.meta.node_params || '');
    window.ndRequest
      .getJSON(url)
      .then(function (data) {
        row.nodes = data.nodes || [];
        box.classList.add('nd_loaded');
        // nodesHtml escapes every value it places
        // eslint-disable-next-line no-unsanitized/property
        box.innerHTML = nodesHtml(row, row.nodes, c);
      })
      .catch(function () {
        // every part is a literal, none of it is data
        // eslint-disable-next-line no-unsanitized/property
        box.innerHTML =
          '<span class="text-danger"><i class="fas fa-triangle-exclamation"></i>&nbsp; Could not load nodes. ' +
          '<a href="#" class="nd_nodes-fetch-retry">Retry</a></span>';
      })
      .finally(function () {
        box.classList.remove('nd_loading');
      });
  };

  /**
   * What the table does once it exists: folds the subinterface rows that
   * start folded, through a filter of this table's own rather than
   * DataTables' global list, and binds the fold toggles and the nodes lists
   * that load when opened.
   * @param {HTMLTableElement} table the table
   * @param {PortsContext} c the table's context
   * @returns {Function} the DataTables initComplete function
   */
  const initComplete = function (table, c) {
    return function () {
      const api = this.api();
      api.rows().every(function () {
        const row = this.data();
        if (row.group && row._folded === undefined) row._folded = startsFolded(row, c.meta.params);
      });
      api.search.fixed('nd_fold', function (str, row) {
        return !row._folded;
      });
      const body = table.tBodies[0];
      body.addEventListener('click', function (evt) {
        const target = /** @type {Element} */ (evt.target);
        const toggle = target.closest('.nd_row-collapser-toggle');
        if (toggle) {
          toggleGroup(api, toggle);
          return;
        }
        const retry = target.closest('.nd_nodes-fetch-retry');
        if (retry) {
          evt.preventDefault();
          loadNodes(api, retry.closest('.nd_nodes-fetch'), c);
        }
      });
      // On capture: netdisco.js rewrites the opener's markup in its own
      // click handler, after which the click target has left the document.
      body.addEventListener(
        'click',
        function (evt) {
          const opener = /** @type {Element} */ (evt.target).closest('.nd_collapse-vlans');
          const total = opener && opener.closest('.nd_nodes-total');
          const box = total && total.nextElementSibling;
          if (box && box.classList.contains('nd_nodes-fetch')) loadNodes(api, box, c);
        },
        true
      );
      api.draw(false);
    };
  };

  // marks a subinterface row with the group it folds into, as ports.tt did
  const createdRow = function (c) {
    return function (tr, row) {
      if (!row.group) return;
      if (row._folded === undefined) row._folded = startsFolded(row, c.meta.params);
      tr.classList.add('nd_collapsible');
      tr.setAttribute('data-collapsed-group', row.group);
      tr.setAttribute('data-is-collapsed', row._folded ? 'true' : 'false');
    };
  };

  // the table's header, from the columns the route chose; the status
  // column has none of its own
  const drawHeader = function (table, columns) {
    const doc = table.ownerDocument;
    const tr = doc.createElement('tr');
    [''].concat(
      columns.map(function (col) {
        return col.label;
      })
    ).forEach(function (label) {
      const th = doc.createElement('th');
      th.textContent = label;
      tr.appendChild(th);
    });
    const thead = doc.createElement('thead');
    thead.appendChild(tr);
    table.textContent = '';
    table.appendChild(thead);
  };

  // The route answered with no rows: the notice every other pane gives, in
  // place of the table.
  const none = function (table) {
    const note = table.ownerDocument.createElement('div');
    note.className = 'col-md-2 alert alert-info';
    note.textContent = 'No matching records.';
    table.replaceWith(note);
  };

  // A line in the table's place while it waits, or when the request failed
  // and the line offers another try.
  const say = function (table, html) {
    table.textContent = '';
    const body = table.ownerDocument.createElement('tbody');
    const row = body.appendChild(table.ownerDocument.createElement('tr'));
    const cell = row.appendChild(table.ownerDocument.createElement('td'));
    // every caller passes a literal
    // eslint-disable-next-line no-unsanitized/property
    cell.innerHTML = html;
    table.appendChild(body);
  };

  // The DataTables options for the rows and columns, the same at the first
  // load and when the columns change.
  const buildOptions = function (table, c, rows, picked) {
    const columns = [dataTableColumn('status', c, true)].concat(
      picked.map(function (col) {
        return dataTableColumn(col.name, c);
      })
    );
    return {
      deferRender: true,
      data: rows,
      columns: columns,
      order: columns.length > 1 ? [[1, 'asc']] : [],
      createdRow: createdRow(c),
      initComplete: initComplete(table, c)
    };
  };

  // What a loaded table keeps to change its columns without the server
  // drawing it again: its context, the rows, ndTables' helpers, the DataTables
  // API, the names of its columns, the column flags whose data the rows hold,
  // and the chain its column changes wait on.
  const TABLES = new WeakMap();

  /**
   * ndTables.loaders.ports: fetches the table's columns and rows from the
   * route in data-nd-source and builds the table from them.
   * @param {HTMLTableElement} table the frame's table
   * @param {Element} root the just-swapped htmx fragment root
   * @param {{build: Function}} helpers ndTables' own, build() among them
   * @returns {Promise<void>} settles once the table is drawn or the failure shown
   */
  const load = function (table, root, helpers) {
    const urls = JSON.parse(table.dataset.ndUrls || '{}');
    if (!table.dataset.ndRetry) {
      table.dataset.ndRetry = '1';
      table.addEventListener('click', function (evt) {
        if (!(/** @type {Element} */ (evt.target).closest('.nd_ports-retry'))) return;
        evt.preventDefault();
        say(table, SPINNER);
        load(table, root, helpers);
      });
    }
    return window.ndRequest
      .getJSON(table.dataset.ndSource)
      .then(function (data) {
        // the pane was submitted again meanwhile, and this answer is not its
        if (!table.isConnected) return;
        if (!data.rows || !data.rows.length) {
          none(table);
          return;
        }
        const c = { urls: urls, meta: data.meta };
        const rows = data.rows;
        const folds = c.meta.params.p_fold_dotzero || c.meta.params.p_fold_subinterfaces;
        if (folds) {
          rows.forEach(function (r) {
            if (r.group) r._folded = startsFolded(r, c.meta.params);
          });
        }
        const options = buildOptions(table, c, rows, data.columns);
        drawHeader(table, data.columns);
        const api = helpers.build(table, root, options);
        const loaded = {};
        Object.keys(c.meta.params || {}).forEach(function (name) {
          if (c.meta.params[name]) loaded[name] = true;
        });
        TABLES.set(table, {
          c: c,
          rows: rows,
          root: root,
          helpers: helpers,
          api: api,
          names: ['status'].concat(
            data.columns.map(function (col) {
              return col.name;
            })
          ),
          loaded: loaded,
          chain: Promise.resolve()
        });
        table.dataset.ndLoaded = '1';
        // a column checkbox changed while the rows were on their way
        if (table.dataset.ndColumnsPending) {
          delete table.dataset.ndColumnsPending;
          applyColumns(table);
        }
      })
      .catch(function (err) {
        if (!table.isConnected) return;
        console.error(err);
        say(
          table,
          '<span class="text-danger"><i class="fas fa-triangle-exclamation"></i>&nbsp; Could not load the ports. ' +
            '<a href="#" class="nd_ports-retry">Retry</a></span>'
        );
      });
  };

  ndTables.loaders.ports = load;

  // --- changing the columns in place ---------------------------------------
  //
  // A Display Columns checkbox applies at once: the table keeps its rows, asks
  // the data route for the columns they lack and nothing else, and is drawn
  // again from them. Drawn again rather than shown and hidden with DataTables'
  // column().visible(): createdCell's attributes, the cell c_nodes and
  // c_neighbors share and its label, and what c_admin makes editable all
  // depend on the set of columns, and are only right when the cells are made
  // anew. Anything else in the sidebar still goes through Update View, as it
  // changes which rows there are or what every node cell holds.

  /**
   * The table's columns for a set of options, as _port_columns in Ports.pm
   * picks them from the same choices: those that are on, with c_nodes folded
   * into c_neighbors when both are.
   * @param {{name: string, label: string}[]} choices meta.choices, in order
   * @param {{[name: string]: any}} params the column flags
   * @returns {{name: string, label: string}[]} the columns, without the status one
   */
  const pickColumns = function (choices, params) {
    const out = [];
    (choices || []).forEach(function (item) {
      if (!params[item.name]) return;
      if (item.name === 'c_nodes' && params.c_neighbors) return;
      let label = item.label;
      if (item.name === 'c_neighbors') label = params.c_nodes ? 'Connected Nodes & Devices' : 'Connected Devices';
      out.push({ name: item.name, label: label });
    });
    return out;
  };

  // The flags whose data the rows hold or could: every column offered, and
  // c_admin, which brings each port's acl_* fields.
  const offeredFlags = function (meta) {
    const out = { c_admin: true };
    (meta.choices || []).forEach(function (item) {
      out[item.name] = true;
    });
    return out;
  };

  /**
   * A URL with its column flags replaced: every name in drop and every c_*
   * parameter taken out, then each name in on put back as the sidebar form
   * sends a ticked box. Everything else in the query is kept as it was.
   * @param {string} url a path with or without a query
   * @param {string[]} drop the flags to take out
   * @param {string[]} on the flags to put back
   * @returns {string} the URL
   */
  const withFlags = function (url, drop, on) {
    const i = url.indexOf('?');
    const query = new URLSearchParams(i === -1 ? '' : url.slice(i + 1));
    const out = new URLSearchParams();
    query.forEach(function (v, k) {
      if (drop.indexOf(k) === -1 && !/^c_/.test(k)) out.append(k, v);
    });
    on.forEach(function (name) {
      out.append(name, 'on');
    });
    const q = out.toString();
    return (i === -1 ? url : url.slice(0, i)) + (q ? '?' + q : '');
  };

  /**
   * The flags to fetch: those ticked and offered whose data the rows do not
   * hold. The search text, the ports whose nodes are fetched and the cell they
   * share are each worked out from c_nodes and c_neighbors together, so one of
   * the two brings the other along when it is ticked.
   * @param {string[]} on the ticked flags
   * @param {{[name: string]: boolean}} loaded the flags whose data the rows hold
   * @param {{[name: string]: boolean}} offered the flags that are columns
   * @returns {string[]} the flags missing
   */
  const missingFlags = function (on, loaded, offered) {
    const missing = on.filter(function (name) {
      return offered[name] && !loaded[name];
    });
    const pair = ['c_nodes', 'c_neighbors'];
    const paired = missing.some(function (name) {
      return pair.indexOf(name) !== -1;
    });
    if (paired) {
      pair.forEach(function (name) {
        if (on.indexOf(name) !== -1 && missing.indexOf(name) === -1) missing.push(name);
      });
    }
    return missing;
  };

  /**
   * The data route's query for only some columns: the table's own source,
   * which holds the filter the rows were chosen by (the sidebar may hold
   * edits not yet submitted), with every column flag out and the missing ones
   * in. No column flag changes which ports there are.
   * @param {string} source the table's data-nd-source
   * @param {string[]} flags every column flag there is
   * @param {string[]} missing the flags to fetch
   * @returns {string} the URL
   */
  const partialQuery = function (source, flags, missing) {
    return withFlags(source, flags, missing);
  };

  const NESTED = ['cells', 'fields', 'hidden_cells', 'data'];

  /**
   * Merges the answer for some columns into the rows the table holds, by
   * port: each key replaced, the plugin column hashes merged one level deep,
   * and the memo of each cell's text dropped. The shared meta gains the
   * plugin column configs, VLAN names and node querystring the answer brings.
   * Nothing is changed when the answer's ports are not the table's, as when
   * the device was discovered again in the meantime.
   * @param {any[]} rows the table's rows
   * @param {any} meta the table's meta
   * @param {any} answer the data route's answer
   * @returns {boolean} whether the answer was merged
   */
  const mergeRows = function (rows, meta, answer) {
    const fresh = (answer && answer.rows) || [];
    const byPort = new Map();
    fresh.forEach(function (r) {
      byPort.set(r.port, r);
    });
    if (fresh.length !== rows.length || byPort.size !== fresh.length) return false;
    const same = rows.every(function (r) {
      return byPort.has(r.port);
    });
    if (!same) return false;
    rows.forEach(function (row) {
      const f = byPort.get(row.port);
      Object.keys(f).forEach(function (k) {
        if (NESTED.indexOf(k) !== -1 && row[k] && f[k] && typeof f[k] === 'object') Object.assign(row[k], f[k]);
        else row[k] = f[k];
      });
      delete row._m;
    });
    const m = answer.meta || {};
    meta.extra = Object.assign({}, meta.extra, m.extra);
    meta.vlan_names = Object.assign({}, meta.vlan_names, m.vlan_names);
    if (m.links) {
      meta.links = m.links;
      meta.link_vars = m.link_vars;
    }
    if (m.node_params) meta.node_params = m.node_params;
    return true;
  };

  // the Display Columns checkboxes, as they are now
  const columnBoxes = function () {
    return Array.prototype.map.call(
      document.querySelectorAll('#ports_form #nd_columns input[type=checkbox]'),
      function (box) {
        return { name: box.name, checked: Boolean(box.checked) };
      }
    );
  };

  // the whole pane asked for again, as Update View does
  const refresh = function () {
    window.htmx.trigger('#ports_form', 'submit');
  };

  // Draws the table again from the rows it holds, for the columns meta.params
  // now names, on the same order, page, page length and filter, kept by
  // column name where they were kept by index.
  const rebuild = function (table, s) {
    const picked = pickColumns(s.c.meta.choices, s.c.meta.params);
    const names = ['status'].concat(
      picked.map(function (col) {
        return col.name;
      })
    );
    // c_nodes and c_neighbors are one cell under either name
    const cell = function (name) {
      return name === 'c_nodes' ? 'c_neighbors' : name;
    };
    const api = s.api;
    const order = [];
    (api.order() || []).forEach(function (o) {
      const pair = Array.isArray(o) ? o : [o.idx, o.dir];
      const i = names.map(cell).indexOf(cell(s.names[pair[0]]));
      if (i > 0) order.push([i, pair[1]]);
    });
    const len = api.page.len();
    const start = len > 0 ? api.page() * len : 0;
    const search = api.search();
    api.destroy();
    // a cell's text can change with the columns beside it (the nodes and
    // neighbors cell, the edit icons under c_admin)
    s.rows.forEach(function (r) {
      delete r._m;
    });
    const options = buildOptions(table, s.c, s.rows, picked);
    if (order.length || names.length < 2) options.order = order;
    options.pageLength = len;
    options.displayStart = start;
    options.search = { search: search };
    // the saved state is of the columns before, by index
    options.stateLoadCallback = function () {
      return null;
    };
    drawHeader(table, picked);
    s.names = names;
    s.api = s.helpers.build(table, s.root, options);
  };

  // Carries the columns shown into what still holds the old ones: the
  // table's source, which Retry asks again, the CSV link, and the address
  // bar, as HX-Replace-Url does for any other change to the tab's options.
  const syncUrls = function (table, drop, on) {
    table.dataset.ndSource = withFlags(table.dataset.ndSource, drop, on);
    const csv = document.getElementById('nd_csv-download');
    const href = csv && csv.getAttribute('href');
    if (href && href !== '#') csv.setAttribute('href', withFlags(href, drop, on));
    const loc = window.location;
    if (loc && window.history && new URLSearchParams(loc.search).get('tab') === 'ports') {
      window.history.replaceState(window.history.state, '', withFlags(loc.pathname + loc.search, drop, on) + loc.hash);
    }
  };

  // One change of the columns, reading the checkboxes as they are when it
  // runs: a series of clicks costs one request per column missing at most.
  const applyNow = function (table, s) {
    const current = function () {
      return table.isConnected && TABLES.get(table) === s;
    };
    if (!current()) return undefined;
    const meta = s.c.meta;
    const offered = offeredFlags(meta);
    const boxes = columnBoxes();
    const changed = boxes.some(function (b) {
      return offered[b.name] && Boolean(meta.params[b.name]) !== b.checked;
    });
    if (!changed) return undefined;
    const on = boxes
      .filter(function (b) {
        return b.checked;
      })
      .map(function (b) {
        return b.name;
      });

    // Port control changed the device under cells the rows still hold the
    // old values of; and c_admin needs the reason dialog that only a frame
    // drawn under it carries.
    const noDialog = on.indexOf('c_admin') !== -1 && !meta.params.c_admin && !document.getElementById('nd_portlog');
    if (table.dataset.ndEdited || noDialog) {
      refresh();
      return undefined;
    }

    const flags = Object.keys(offered).concat(
      boxes.map(function (b) {
        return b.name;
      })
    );
    const missing = missingFlags(on, s.loaded, offered);
    if (!missing.length) {
      boxes.forEach(function (b) {
        if (offered[b.name]) meta.params[b.name] = b.checked ? 1 : 0;
      });
      rebuild(table, s);
      syncUrls(table, flags, on);
      return undefined;
    }

    s.api.processing(true);
    return window.ndRequest.getJSON(partialQuery(table.dataset.ndSource, flags, missing)).then(
      function (data) {
        if (!current()) return undefined;
        s.api.processing(false);
        if (!mergeRows(s.rows, meta, data)) {
          refresh();
          return undefined;
        }
        missing.forEach(function (name) {
          s.loaded[name] = true;
        });
        // boxes ticked meanwhile are fetched now, those unticked are not drawn
        return applyNow(table, s);
      },
      function (err) {
        if (!current()) return undefined;
        console.error(err);
        s.api.processing(false);
        refresh();
        return undefined;
      }
    );
  };

  /**
   * Shows the columns the Display Columns checkboxes ask for, fetching only
   * those the rows lack. Changes to one table wait for each other.
   * @param {HTMLTableElement} table a loaded Ports table
   * @returns {Promise<void>} settles once the table shows the columns
   */
  const applyColumns = function (table) {
    const s = TABLES.get(table);
    if (!s) return Promise.resolve();
    s.chain = s.chain
      .then(function () {
        return applyNow(table, s);
      })
      .catch(console.error);
    return s.chain;
  };

  // A table still loading takes the change once its rows are in; a site's
  // own ports.tt, a pane that found no ports or one that failed keep needing
  // Update View.
  const onColumnChange = function (evt) {
    const box = evt.target;
    if (!(box && box.matches && box.matches('#ports_form #nd_columns input[type=checkbox]'))) return;
    const table = document.querySelector('#ports_pane table[data-nd-loader="ports"]');
    if (!table) return;
    if (table.dataset.ndLoaded) applyColumns(table);
    else if (table.dataset.ndLoaderStarted) table.dataset.ndColumnsPending = '1';
  };
  if (typeof document.addEventListener === 'function') document.addEventListener('change', onColumnChange);

  /**
   * Registers how a plugin draws its own column, named by the "renderer" of
   * its register_device_port_column. The row's data.<column name> holds what
   * the column's json coderef returned.
   * @param {string} name the renderer's name
   * @param {{html: Function, value?: Function, filter?: Function, attrs?: Function}} def
   *   html(row, context) is the cell's markup and must escape what it places;
   *   value(row, context) is what the column sorts on, defaulting to the text
   *   of the markup; filter(row, context) is what it filters on, defaulting to
   *   the same; attrs(row, context) is an object of the td's own attributes
   * @returns {void}
   */
  const registerColumn = function (name, def) {
    REGISTERED[name] = def;
  };

  return {
    columns: COLUMNS,
    columnFor: columnFor,
    dataTableColumn: dataTableColumn,
    nodesHtml: nodesHtml,
    ttUri: ttUri,
    startsFolded: startsFolded,
    toggleGroup: toggleGroup,
    registerColumn: registerColumn,
    esc: esc,
    enc: enc,
    load: load,
    pickColumns: pickColumns,
    withFlags: withFlags,
    missingFlags: missingFlags,
    partialQuery: partialQuery,
    mergeRows: mergeRows,
    applyColumns: applyColumns,
    onColumnChange: onColumnChange
  };
})();
