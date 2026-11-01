package App::Netdisco::Web::Plugin::Device::Ports;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Util::Permission qw/acl_matches permitted_by_acl/;
use App::Netdisco::Util::Port qw/port_acl_service port_acl_pvid port_acl_name/;
use App::Netdisco::Web::Plugin;

use List::MoreUtils 'singleton';
use NetAddr::MAC ();
use DBIx::Class::ResultClass::HashRefInflator;
use URI::Escape 'uri_escape';

register_device_tab({ tag => 'ports', label => 'Ports', provides_csv => 1 });

# $nodes_name names a has_many relation, but the source it reads from is a
# different name again.
my %node_result_class = (
    nodes                 => 'Node',
    active_nodes          => 'Virtual::ActiveNode',
    nodes_with_age        => 'Virtual::NodeWithAge',
    active_nodes_with_age => 'Virtual::ActiveNodeWithAge',
);

# Fetches nodes for one device and groups them by port name. Split out from
# the route so xt can call it without a session, the route being require_login.
#
# HashRefInflator returns plain hashrefs, and Template Toolkit's FOREACH over
# a bare hashref iterates its key/value pairs instead of treating it as one
# item, so manufacturer (belongs_to) and netbios (might_have) are wrapped in
# an arrayref to restore the one-row-or-none shape the template expects.
# wireless is has_many and arrives as an arrayref already.
sub _stitch_nodes {
    my ($schema, $device_ip, $rows, $nodes_name, $ips_name, $node_order,
        $extra_prefetch, $only_ports) = @_;

    my %cond = (switch => $device_ip);
    $cond{port} = { -in => $only_ports }
      if $only_ports and scalar @$only_ports;

    my $node_rs = $schema->resultset($node_result_class{$nodes_name})
      ->search(\%cond, {
        order_by => $node_order,
        prefetch => [ $ips_name, @{ $extra_prefetch || [] } ],
      });
    $node_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');

    my %nodes_by_port = ();
    for my $node ($node_rs->all) {
        $node->{stitched_ips} = delete $node->{$ips_name} || [];
        $node->{net_mac} = NetAddr::MAC->new(mac => ($node->{mac} || ''));
        $node->{manufacturer} = [ $node->{manufacturer} ] if $node->{manufacturer};
        $node->{netbios} = [ $node->{netbios} ] if $node->{netbios};
        push @{ $nodes_by_port{ $node->{port} } }, $node;
    }

    # attached here rather than by the caller, so a test exercises the same
    # key the template reads.
    $_->{stitched_nodes} = ($nodes_by_port{ $_->port } || []) for @$rows;
    return;
}

# Decides whether to fetch nodes for this view, and how widely, as the
# $only_ports argument to _stitch_nodes. Kept free of param() so xt can pin
# the decision without a session.
#
# The neighbors-only branch is for a site's own older ports.tt ($legacy), which
# finds the neighbor's MAC among the nodes; the shipped one uses _neighbor_macs.
#
# Returns undef to fetch nothing, or an arrayref for $only_ports: empty means
# the whole device, non-empty scopes the fetch to those ports. The c_nodes
# branch's empty arrayref only reaches the CSV export as written: the HTML
# path narrows it again via _threshold_scope before any fetch runs.
sub _node_fetch_scope {
    my ($want_nodes, $want_neighbors, $rows, $legacy) = @_;

    return [] if $want_nodes;
    return undef if not ($want_neighbors and $legacy);

    my @neighbor_ports = map { $_->port } grep { $_->remote_ip } @$rows;
    return undef if not scalar @neighbor_ports;
    return \@neighbor_ports;
}

# The MAC behind each port's remote_ip, in one query, so c_neighbors alone no
# longer stitches nodes. Picks what the stitch picked: the first node in
# _node_display_options' order carrying the IP.
sub _neighbor_macs {
    my ($schema, $device_ip, $nodes_name, $ips_name) = @_;

    my $family = ($ips_name eq 'ip4s') ? 'AND family(i.ip) = 4'
               : ($ips_name eq 'ip6s') ? 'AND family(i.ip) = 6'
               : '';

    my $sql = sprintf(q{
        SELECT DISTINCT ON (n.port) n.port, n.mac::text
          FROM device_port p
          JOIN node n ON n.switch = p.ip AND n.port = p.port
          JOIN node_ip i ON i.mac = n.mac AND i.active = n.active
                        AND i.ip = p.remote_ip
         WHERE p.ip = ? AND p.remote_ip IS NOT NULL %s %s
         ORDER BY n.port,
                  regexp_replace(COALESCE(n.vlan, '0'), '[^0-9]*' ,'0') :: integer,
                  n.mac
    }, _shadow_active_fragment($nodes_name), $family);

    my $macs = $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->selectall_arrayref($sql, undef, $device_ip);
    });

    return { map {; $_->[0] => $_->[1] } @$macs };
}

# PoE, SSIDs and the last comment, one query each keyed by port: prefetched,
# power and ssid slowed the port query, and last_comment ran a query per port.
# Kept under keys of their own so templates do not call the relation methods.
sub _port_power {
    my ($schema, $device_ip) = @_;
    my $rows = $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->selectall_arrayref(q{
          SELECT port, admin, status, class, power
            FROM device_port_power WHERE ip = ?
      }, { Slice => {} }, $device_ip);
    });
    return { map {; (delete $_->{port}) => $_ } @$rows };
}

# sorted; the prefetch gave no order
sub _port_ssids {
    my ($schema, $device_ip) = @_;
    my $rows = $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->selectall_arrayref(q{
          SELECT port, ssid FROM device_port_ssid
           WHERE ip = ? AND ssid IS NOT NULL
           ORDER BY port, ssid
      }, undef, $device_ip);
    });
    my %ssids = ();
    push @{ $ssids{ $_->[0] } }, $_->[1] for @$rows;
    return \%ssids;
}

# DevicePort's last_comment, for every port at once
sub _last_comments {
    my ($schema, $device_ip) = @_;
    my $rows = $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->selectall_arrayref(q{
          SELECT DISTINCT ON (port) port, log
            FROM device_port_log
           WHERE ip = ?
           ORDER BY port, creation DESC
      }, undef, $device_ip);
    });
    return { map {; $_->[0] => $_->[1] } @$rows };
}

# n_archived swaps $nodes_name to nodes, which is the whole table rather than
# the archived half, so a shadow built with active = 0 there would drop the
# active nodes back out and a MAC visible on screen would stop being findable.
# Derived from $nodes_name so this and %node_result_class cannot drift apart.
sub _shadow_active_fragment {
    my ($nodes_name) = @_;
    return $nodes_name =~ m/^active/ ? 'AND n.active' : '';
}

# Builds the DataTables search shadow: one string per port carrying every
# node's mac, ip, dns and vlan text, plus ssid and netbios when asked for, so
# the filter can find a node whose markup this response does not render.
# Built in one statement rather than by concatenating the fetched rows in
# Perl, which costs more than the render it exists to save.
#
# The node_ip lateral's "active = n.active" mirrors Node's ips relationship,
# which joins foreign.active => self.active, so an archived node gets archived
# IPs. Get it wrong and the filter matches archived IPs that are not on
# screen. node_wireless and node_nbt are keyed on mac alone, with no active
# condition, so their laterals match that instead.
#
# vlan has no n_* guard in the template and is always included. ssid, netbios
# and vendor are joined only under their own guards: a field the cell does not
# render need not be findable, and each join has a real cost.
sub _attach_search_shadow {
    my ($schema, $device_ip, $rows, $active_fragment, $want_ssid, $want_netbios,
        $mac_format, $want_vendor) = @_;

    my ($ssid_select, $ssid_join) = ('', '');
    if ($want_ssid) {
        $ssid_select = q{ || ' ' || COALESCE(w.txt, '')};
        $ssid_join = q{
          LEFT JOIN LATERAL (
            SELECT string_agg(ssid, ' ') AS txt
              FROM node_wireless WHERE mac = n.mac) w ON true};
    }

    # nbuser is a logged-in user rather than the machine's own NetBIOS
    # hostname, so nbname does not cover it, and nbt.ip is not always one of
    # the node's own IPs, so the node_ip lateral does not either. The
    # '[No User]' fallback the template renders is left out: it would match
    # every node that has no NetBIOS user.
    my ($netbios_select, $netbios_join) = ('', '');
    if ($want_netbios) {
        $netbios_select = q{ || ' ' || COALESCE(b.txt, '')};
        $netbios_join = q{
          LEFT JOIN LATERAL (
            SELECT string_agg(COALESCE(nbname, '') || ' ' || COALESCE(domain, '')
                 || ' ' || COALESCE(nbuser, '') || ' ' || COALESCE(ip::text, ''), ' ') AS txt
              FROM node_nbt WHERE mac = n.mac) b ON true};
    }

    # manufacturer is belongs_to on the node's oui, so at most one row and a
    # plain LEFT JOIN rather than a lateral. abbrev, not company, because
    # abbrev is what the cell renders.
    my ($vendor_select, $vendor_join) = ('', '');
    if ($want_vendor) {
        $vendor_select = q{ || ' ' || COALESCE(m.abbrev, '')};
        $vendor_join = q{
          LEFT JOIN manufacturer m ON m.base = n.oui};
    }

    # The cell renders the MAC through mac_format_call, so on any setting but
    # IEEE the string on screen is not the one Postgres stores and a filter on
    # the visible MAC would miss. The displayed form is carried beside the
    # canonical one rather than instead of it, so a pasted IEEE address keeps
    # working whatever the setting. IEEE needs no entry here: it is exactly
    # what mac::text already gives. Kept in step with NetAddr::MAC's as_cisco,
    # as_microsoft and as_sun, which is what the template calls.
    my %mac_as = (
        cisco     => q{regexp_replace(replace(n.mac::text, ':', ''),
                         '(.{4})(.{4})(.{4})', '\1.\2.\3')},
        microsoft => q{replace(n.mac::text, ':', '-')},
        sun       => q{replace(regexp_replace(n.mac::text,
                         '(^|:)0([0-9a-f])', '\1\2', 'g'), ':', '-')},
    );
    my $mac_select = '';
    if ($mac_format and my $expr = $mac_as{ lc $mac_format }) {
        $mac_select = qq{ || ' ' || $expr};
    }

    my $sql = sprintf(q{
        SELECT n.port,
               string_agg(n.mac::text || ' ' || COALESCE(n.vlan, '') || ' '
                 || COALESCE(i.txt, '')%s%s%s%s, ' ') AS s
          FROM node n
          LEFT JOIN LATERAL (
            SELECT string_agg(ip::text || ' ' || COALESCE(dns, ''), ' ') AS txt
              FROM node_ip WHERE mac = n.mac AND active = n.active) i ON true
          %s%s%s
         WHERE n.switch = ? %s
         GROUP BY n.port
    }, $ssid_select, $netbios_select, $vendor_select, $mac_select,
       $ssid_join, $netbios_join, $vendor_join, $active_fragment);

    my $shadow = $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->selectall_arrayref($sql, undef, $device_ip);
    });

    my %shadow_by_port = map {; $_->[0] => ($_->[1] || '') } @$shadow;
    $_->{nodes_search} = ($shadow_by_port{ $_->port } || '') for @$rows;
    return;
}

# The nodes cell and the neighbors cell are one <td>, and data-search on a
# <td> replaces that cell's whole search text rather than adding to it, so a
# port's own neighbor identity has to be appended or it stops being findable
# once c_nodes is on.
#
# remote_ip, remote_port, remote_dns, remote_id and remote_type are
# device_port columns (remote_dns via the with_properties join the route
# always applies) and are safe to read whatever the params say. neighbor_ip
# and neighbor_dns come from a +select added only under c_neighbors, and
# get_column dies for a column that was never selected. remote_inventory is a
# method, not a column: it reads columns only with_remote_inventory selects,
# which the route applies only under n_inventory, so it dies the same way
# unless guarded on that flag.
sub _augment_neighbor_search {
    my ($rows, $want_neighbors, $want_inventory) = @_;

    for my $row (@$rows) {
        my @extra = grep { defined and length }
          ($row->remote_ip, $row->remote_port, $row->remote_dns,
           $row->remote_id, $row->remote_type);
        push @extra, grep { defined and length }
          ($row->get_column('neighbor_ip'), $row->get_column('neighbor_dns'))
          if $want_neighbors;
        if ($want_inventory) {
            my $inventory = $row->remote_inventory;
            push @extra, $inventory if defined $inventory and length $inventory;
        }

        next unless @extra;
        $row->{nodes_search} = join ' ', grep { length } ($row->{nodes_search}, @extra);
    }
    return;
}

# Shared with the one-port route below: the node source and the ordering and
# prefetch terms must not drift between the two, or the deferred fetch draws
# its rows in a different order than the eager path would have. Kept free of
# the c_nodes/c_neighbors gate the main route used to apply to the ordering
# and prefetch terms, because the deferred fetch never sends either param and
# an empty @node_order would leave it unordered.
sub _node_display_options {
    my $nodes_name = (param('n_archived') ? 'nodes' : 'active_nodes');
    $nodes_name .= '_with_age' if param('n_age');

    my $ips_name = ((param('n_ip4') and param('n_ip6')) ? 'ips'
                   : param('n_ip4') ? 'ip4s'
                   : 'ip6s');

    my @node_order = (
      \qq{regexp_replace(COALESCE(me.vlan, '0'), '[^0-9]*' ,'0') :: integer},
      'me.mac',
      "${ips_name}.ip",
    );

    my @extra_prefetch = ();
    push @extra_prefetch, 'wireless' if param('n_ssid');
    push @extra_prefetch, 'netbios' if param('n_netbios');
    push @extra_prefetch, 'manufacturer' if param('n_vendor');

    return ($nodes_name, $ips_name, \@node_order, \@extra_prefetch);
}

# One query, run once per c_nodes request rather than once per row: reads the
# same table _attach_search_shadow does, under the same active fragment, so a
# port cannot say "N nodes" here and expand to a different number there.
sub _count_nodes_by_port {
    my ($schema, $device_ip, $rows, $active_fragment) = @_;

    my $sql = sprintf(q{
        SELECT n.port, count(*) AS n
          FROM node n
         WHERE n.switch = ? %s
         GROUP BY n.port
    }, $active_fragment);

    my $counts = $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->selectall_arrayref($sql, undef, $device_ip);
    });

    my %count_by_port = map {; $_->[0] => $_->[1] } @$counts;
    $_->{node_count} = ($count_by_port{ $_->port } || 0) for @$rows;
    return \%count_by_port;
}

# Carries the display options that change how a node row renders, built once
# here rather than in the template, so the deferred fetch draws the same
# markup the eager path would have. mac_format feeds mac_format_call in
# Web.pm, which every node's MAC is rendered through. Kept free of param()
# so xt can pin the querystring without a session.
sub _deferred_node_params {
    my ($n_ip4, $n_ip6, $n_dns, $n_age, $n_ssid, $n_vendor, $n_netbios,
        $n_archived, $mac_format) = @_;

    my $qs = '';
    $qs .= '&n_ip4=1' if $n_ip4;
    $qs .= '&n_ip6=1' if $n_ip6;
    $qs .= '&n_dns=1' if $n_dns;
    $qs .= '&n_age=1' if $n_age;
    $qs .= '&n_ssid=1' if $n_ssid;
    $qs .= '&n_vendor=1' if $n_vendor;
    $qs .= '&n_netbios=1' if $n_netbios;
    $qs .= '&n_archived=1' if $n_archived;
    $qs .= '&mac_format=' . uri_escape($mac_format) if $mac_format;
    return $qs;
}

# Ports at or under the threshold get their own row fetched. For a site's own
# ports.tt ($want_neighbors is then c_neighbors), a port over it still gets
# one when it might carry a neighbor's own MAC, since that template reads
# stitched_nodes for it regardless of the node list's own threshold. The
# shipped templates read _neighbor_macs instead and pass false, so an
# over-threshold trunk port is never stitched just to throw the render away.
# Kept free of param() and setting() so xt can pin the decision without a
# session.
sub _threshold_scope {
    my ($threshold, $want_neighbors, $count_by_port, $rows) = @_;
    return [ map { $_->port }
      grep { ($count_by_port->{ $_->port } || 0) <= $threshold
             or ($want_neighbors and $_->remote_ip) } @$rows ];
}

# The decorated, filtered and grouped ports for the HTML, CSV and JSON outputs.
# Runs inside a route only; returns undef when there are no rows.
# $opt->{legacy} is for a site's own older ports.tt.
sub _port_rows {
    my ($opt) = @_;
    $opt ||= {};
    my $q = param('q');
    my $prefer = param('prefer');
    $prefer = ''
      unless defined $prefer and $prefer =~ m/^(?:port|name|vlan)$/;

    my $device = schema(vars->{'tenant'})->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);
    my $set = $device->ports->with_properties->with_custom_fields;

    # refine by ports if requested
    my $f = param('f');
    if ($f) {
        if (($prefer eq 'vlan') or (not $prefer and $f =~ m/^\d+$/)) {
            return unless $f =~ m/^\d+$/;
        }
        else {
            if (param('partial')) {
                # change wildcard chars to SQL
                $f =~ s/\*/%/g;
                $f =~ s/\?/_/g;
                # set wildcards at param boundaries
                if ($f !~ m/[%_]/) {
                    $f =~ s/^\%*/%/;
                    $f =~ s/\%*$/%/;
                }
                # enable ILIKE op
                $f = { (param('invert') ? '-not_ilike' : '-ilike') => $f };
            }
            elsif (param('invert')) {
                $f = { '!=' => $f };
            }

            if (($prefer eq 'port') or not $prefer and
                $set->search({-or => ['me.port' => $f, 'me.descr' => $f]})->count) {

                $set = $set->search({
                  -or => [
                    'me.port' => $f,
                    'me.descr' => $f,
                    'me.slave_of' => $f,
                  ],
                });
            }
            else {
                $set = $set->search({'me.name' => $f});
                return unless $set->count;
            }
        }
    }

    # filter for port status if asked
    my %port_state = map {$_ => 1}
      (ref [] eq ref param('port_state') ? @{param('port_state')}
        : param('port_state') ? param('port_state') : ());

    return unless scalar keys %port_state;

    if (exists $port_state{free}) {
        if (scalar keys %port_state == 1) {
            $set = $set->only_free_ports({
              age_num => (param('age_num') || 3),
              age_unit => (param('age_unit') || 'months')
            });
        }
        else {
            $set = $set->with_is_free({
              age_num => (param('age_num') || 3),
              age_unit => (param('age_unit') || 'months')
            });
        }
        delete $port_state{free};
        # showing free ports requires showing down ports
        ++$port_state{down};
    }

    if (scalar keys %port_state < 3) {
        my @combi = ();

        push @combi, {'me.up' => 'up'}
          if exists $port_state{up};
        push @combi, {'me.up_admin' => 'up', 'me.up' => { '!=' => 'up'}}
          if exists $port_state{down};
        push @combi, {'me.up_admin' => { '!=' => 'up'}}
          if exists $port_state{shut};

        $set = $set->search({-or => \@combi});
    }

    # so far only the basic device_port data
    # now begin to join tables depending on the selected columns/options

    # get vlans on the port
    # leave this query dormant (lazy) unless c_vmember is set or vlan filtering
    my $vlans = $set->search(
      { param('p_hide1002') ?
        (-or => ['port_vlans.vlan' => {'<', '1002'},
                 'port_vlans.vlan' => {'>', '1005'}]) : ()
      }, {
      select => [
        'port',
        { count     => 'port_vlans.vlan', -as => 'vlan_count' },
        { array_agg => \q{port_vlans.vlan ORDER BY port_vlans.vlan}, -as => 'vlan_set' },
        { array_agg => \q{COALESCE(NULLIF(vlan_entry.description,''), vlan_entry.vlan::text) ORDER BY vlan_entry.vlan}, -as => 'vlan_name_set' },
      ],
      join => {'port_vlans' => 'vlan_entry'},
      group_by => 'me.port',
    });

    if (param('c_vmember') or ($prefer eq 'vlan') or (not $prefer and $f =~ m/^\d+$/)) {
        $vlans = { map {(
          $_->port => {
            # DBIC smart enough to work out this should be an arrayref :)
            vlan_count => $_->get_column('vlan_count'),
            vlan_set   => $_->get_column('vlan_set'),
            vlan_name_set => $_->get_column('vlan_name_set'),
          },
        )} $vlans->all };
    }

    if (param('p_vlan_names')) {
        $set = $set->search({}, {
          'join' => 'native_vlan',
          '+select' => [qw/native_vlan.description/],
          '+as'     => [qw/native_vlan_name/],
        });
    }

    # get aggregate master status (self join)
    $set = $set->search({}, {
      'join' => 'agg_master',
      '+select' => [qw/agg_master.up_admin agg_master.up/],
      '+as'     => [qw/agg_master_up_admin agg_master_up/],
    });

    # make sure query asks for formatted timestamps when needed
    $set = $set->with_times if param('c_lastchange');

    # what kind of nodes are we interested in? node_order is qualified
    # against the node source, never $set: see DevicePort's
    # order_by_port_name for why the port key has to lead there. Fetched
    # separately and joined by port name below, not prefetched: one prefetch
    # of ports to nodes to IPs returns the product of all three and DBIC
    # inflates every row of it. _stitch_nodes still prefetches IPs and
    # wireless together off the node, which reintroduces that product, but
    # scoped to one node's own rows rather than every port's.
    my ($nodes_name, $ips_name, $node_order, $extra_prefetch)
      = _node_display_options();

    # retrieve neighbor devices, if asked for
    #$set = $set->search({}, { prefetch => [{neighbor_alias => 'device'}] })
    #  if param('c_neighbors');
    # retrieve neighbor devices, if asked for
    $set = $set->search({}, {
      join => 'neighbor_alias',
      '+select' => ['neighbor_alias.ip', 'neighbor_alias.dns'],
      '+as'     => ['neighbor_ip', 'neighbor_dns'],
    }) if param('c_neighbors');

    # also get remote LLDP inventory if asked for
    $set = $set->with_remote_inventory if param('n_inventory');

    # Ordered in the database rather than after the fetch. The order is
    # portsort.js's, which is the one the browser shows, so this replaces a
    # sort_port pass whose result the browser overwrote anyway. $node_order
    # must not be added here: $set has its own mac and vlan columns and would
    # silently order by those instead.
    $set = $set->order_by_port_name();

    # run query
    my @results = $set->all;

    # see _port_power for why these are not prefetched
    if (param('c_power')) {
        my $power = _port_power(schema(vars->{'tenant'}), $device->ip);
        $_->{port_power} = $power->{ $_->port } for @results;
    }
    if (param('c_ssid')) {
        my $ssids = _port_ssids(schema(vars->{'tenant'}), $device->ip);
        $_->{port_ssids} = ($ssids->{ $_->port } || []) for @results;
    }
    if (param('c_comment')) {
        my $comments = _last_comments(schema(vars->{'tenant'}), $device->ip);
        $_->{port_comment} = $comments->{ $_->port } for @results;
    }

    if (param('c_neighbors')) {
        my $macs = _neighbor_macs(schema(vars->{'tenant'}), $device->ip,
          $nodes_name, $ips_name);
        $_->{neighbor_net_mac} = NetAddr::MAC->new(mac => $macs->{ $_->port })
          for grep { exists $macs->{ $_->port } } @results;
    }

    # fetch and attach nodes by port name, rather than prefetching them
    my $node_fetch_scope = _node_fetch_scope(
      scalar param('c_nodes'), scalar param('c_neighbors'), \@results,
      $opt->{legacy});

    my $deferred_node_params = '';

    if (defined $node_fetch_scope) {
        my $only_ports = $node_fetch_scope;
        my $skip_stitch = 0;

        # ports_csv.tt has no collapse threshold and reads every port's
        # stitched_nodes unconditionally, so this scoping only applies to
        # the HTML fragment: a CSV export still gets the whole device.
        if (param('c_nodes') and request->is_ajax) {
            my $count_by_port = _count_nodes_by_port(schema(vars->{'tenant'}),
              $device->ip, \@results, _shadow_active_fragment($nodes_name));

            # Ports over the threshold render a count and an empty div that
            # fetches its own rows; fetching them here would build markup
            # that netdisco.css hides on arrival.
            $only_ports = _threshold_scope(
              setting('devport_nodes_collapse_threshold'),
              (param('c_neighbors') and $opt->{legacy}),
              $count_by_port, \@results);
            $skip_stitch = 1 unless scalar @$only_ports;

            $deferred_node_params = _deferred_node_params(
              scalar param('n_ip4'), scalar param('n_ip6'),
              scalar param('n_dns'), scalar param('n_age'),
              scalar param('n_ssid'), scalar param('n_vendor'),
              scalar param('n_netbios'), scalar param('n_archived'),
              scalar param('mac_format'));
        }

        _stitch_nodes(schema(vars->{'tenant'}), $device->ip, \@results,
          $nodes_name, $ips_name, $node_order, $extra_prefetch, $only_ports)
          unless $skip_stitch;
    }

    # Gated on c_nodes alone, not c_neighbors like the stitch above: the
    # template emits data-search only under c_nodes, so the neighbors-only
    # view would build this for nothing.
    if (param('c_nodes')) {
        _attach_search_shadow(schema(vars->{'tenant'}), $device->ip, \@results,
          _shadow_active_fragment($nodes_name),
          scalar param('n_ssid'), scalar param('n_netbios'),
          scalar param('mac_format'), scalar param('n_vendor'));
        _augment_neighbor_search(\@results, scalar param('c_neighbors'),
          scalar param('n_inventory'));
    }

    # filter for tagged vlan using existing agg query,
    # which is better than join inflation
    if (($prefer eq 'vlan') or (not $prefer and $f =~ m/^\d+$/)) {
      if (param('invert')) {
        @results = grep {
            (!defined $_->vlan or $_->vlan ne $f)
              and
            (0 == scalar grep {defined and $_ ne $f} @{ $vlans->{$_->port}->{vlan_set} })
        } @results;
      }
      else {
        @results = grep {
            (defined $_->vlan and $_->vlan eq $f)
              or
            (scalar grep {defined and $_ eq $f} @{ $vlans->{$_->port}->{vlan_set} })
        } @results;
      }
    }

    # filter out hidden ones
    if (not param('p_include_hidden')) {
        my $port_map = {};
        my %to_hide  = ();

        map { push @{ $port_map->{$_->port} }, $_ }
             grep { $_->port }
             @results;

        map { push @{ $port_map->{$_->port} }, $_ }
            grep { $_->port }
            $device->device_ips()->all;

        foreach my $map (@{ setting('hide_deviceports')}) {
            next unless ref {} eq ref $map;

            foreach my $key (sort keys %$map) {
                # lhs matches device, rhs matches port
                next unless $key and $map->{$key};
                next unless acl_matches($device, $key);

                foreach my $port (sort keys %$port_map) {
                    next unless acl_matches($port_map->{$port}, $map->{$key});
                    ++$to_hide{$port};
                }
            }
        }

        @results = grep { ! exists $to_hide{$_->port} } @results;
    }

    # empty set would be a 'no records' msg
    return unless scalar @results;

    # collapsible subinterface groups
    my %port_has_dot_zero = ();
    my %port_subinterface_count = ();
    my $subinterfaces_match = (setting('subinterfaces_match') || qr/(.+)\.\d+/);

    foreach my $port (@results) {
        if ($port->port =~ m/^${subinterfaces_match}$/) {
            my $parent = $1;
            next unless defined $parent;
            ++$port_subinterface_count{$parent};
            ++$port_has_dot_zero{$parent}
              if $port->port =~ m/\.0$/
                and ($port->type and $port->type =~ m/^(?:propVirtual|ieee8023adLag)$/i);
            $port->{subinterface_group} = $parent;
        }
    }

    # one pass to index the rows by port name. the two lookups below used to
    # grep @results, re-reading every row once per parent, and on a wireless
    # controller where every port is subinterface-shaped that is the whole
    # request: 3650 parents each reading all 7300 rows and matching none of
    # them, because the bare parent port does not exist (see 1479).
    my %port_row = ();
    $port_row{ $_->port } = $_ for @results;

    foreach my $parent (keys %port_subinterface_count) {
        my $parent_port = $port_row{$parent}
          or next; # 1479 we've seen subinterfaces without parents
        $parent_port->{has_subinterface_group} = true;
        $parent_port->{has_only_dot_zero_subinterface} = true
          if exists $port_has_dot_zero{$parent}
            and $port_subinterface_count{$parent} == 1
            and ($parent_port->type
              and $parent_port->type =~ m/^(?:ethernetCsmacd|ieee8023adLag)$/i);
        if ($parent_port->{has_only_dot_zero_subinterface}) {
            my $dotzero_port = $port_row{"${parent}.0"};
            $dotzero_port->{is_dot_zero_subinterface} = true;
        }
    }

    # add acl on port config
    # this has the merged yaml and database config
    if (param('c_admin') and user_has_role('port_control')) {
      # for native vlan change
      map {$_->{port_acl_pvid} = port_acl_pvid($_, $device, logged_in_user)} @results;
      # for up/down and poe
      map {$_->{port_acl_service} = port_acl_service($_, $device, logged_in_user)} @results;
      # for name/descr change
      map {$_->{port_acl_name} = ($_->{port_acl_service} || # if service true then this is OK
                                  port_acl_name($_, $device, logged_in_user))} @results;
    }

    # filter the tags by hide_tags setting
    my @hide = @{ setting('hide_tags')->{'device_port'} };
    map { $_->{filtered_tags} = [ singleton (@{ $_->tags || [] }, @hide, @hide) ] } @results;

    # pretty print the port running speed
    use App::Netdisco::Util::Port 'to_speed';
    map { $_->{speed_running} = to_speed( $_->speed ) } @results;

    return {
      results => \@results,
      vlans   => $vlans,
      device  => $device,
      nodes_name => $nodes_name,
      ips_name   => $ips_name,
      deferred_node_params => $deferred_node_params,
    };
}

# Whether this is a site's ajax/device/ports.tt from before the neighbor's
# MAC came as neighbor_net_mac: one that reads stitched_nodes, where it used
# to find it, and not neighbor_net_mac. TT comments are left out, so a note
# naming either decides nothing. The site-local rule ports-neighbor-mac tells
# the admin about such a copy.
sub _ports_template_is_legacy {
    my ($text) = @_;
    return 0 if not defined $text;
    (my $code = $text) =~ s/\[%#.*?%\]//gs;
    return ($code =~ m/\bstitched_nodes\b/
            and $code !~ m/\bneighbor_net_mac\b/) ? 1 : 0;
}

# The same for the template that resolves, cached by file and mtime.
my %template_legacy = ();
sub _legacy_ports_template {
    my $file = engine('template')->view('ajax/device/ports') or return 0;
    my $mtime = (stat $file)[9] || 0;
    my $known = $template_legacy{$file};
    if (not $known or $known->{mtime} != $mtime) {
        open my $fh, '<:encoding(UTF-8)', $file or return 0;
        my $text = do { local $/; <$fh> };
        $known = $template_legacy{$file}
          = { mtime => $mtime, legacy => _ports_template_is_legacy($text) };
    }
    return $known->{legacy};
}


# The table's columns, as ports.tt's <thead> loop chose them: c_admin is a mode,
# c_links needs links configured, c_nodes and c_neighbors share one column, and
# a hidden plugin column is left out. The browser adds the status column.
sub _port_columns {
    my ($p, $port_columns, $has_ext_links) = @_;

    my @cols = ();
    foreach my $item (@{ $port_columns || [] }) {
        my $name = $item->{name};
        next if $name eq 'c_admin';
        next if $name eq 'c_links' and not $has_ext_links;
        next if $name eq 'c_nodes' and $p->{c_nodes} and $p->{c_neighbors};
        next unless $p->{$name};
        next if $item->{hidden};

        my $label = $item->{label};
        $label = ($p->{c_nodes} ? 'Connected Nodes & Devices' : 'Connected Devices')
          if $name eq 'c_neighbors';

        push @cols, {
          name => $name,
          label => (defined $label ? $label : ''),
        };
    }
    return \@cols;
}

# A MAC through the NetAddr::MAC method $call names, undef when it is not a MAC
# (a NAC user name falls through to its text).
sub _format_mac {
    my ($mac, $call) = @_;
    return undef unless defined $mac and length $mac;
    my $net_mac = (ref $mac ? $mac
      : eval { NetAddr::MAC->new(mac => $mac) }) or return undef;
    return $net_mac->${\($call || 'as_ieee')};
}

# The NetAddr::MAC method for mac_format, as Web.pm's mac_format_call.
sub _mac_format_call {
    my ($format) = @_;
    my $call = 'as_'. lc($format || 'ieee');
    return (NetAddr::MAC->can($call) ? $call : 'as_ieee');
}

# One node of a port's connected nodes. The node behind the neighbor's own
# address is marked, not left out: port_nodes.tt skipped it but still counted
# it as first or last. $opt: p (the n_* options), mac_format_call.
sub _node_json {
    my ($node, $remote_ip, $opt) = @_;
    my $p = $opt->{p} || {};

    my %n = (mac => _format_mac($node->{net_mac}, $opt->{mac_format_call}));
    $n{vlan} = $node->{vlan} if defined $node->{vlan} and length $node->{vlan};
    $n{archived} = 1 if not $node->{active};
    $n{age} = $node->{time_last_age}
      if $p->{n_age} and defined $node->{time_last_age};

    my @ips = @{ $node->{stitched_ips} || [] };
    $n{neighbor} = 1
      if $remote_ip and grep { $_->{ip} eq $remote_ip } @ips;

    $n{ips} = [ map {{
      ip => $_->{ip},
      ((defined $_->{dns} and length $_->{dns}) ? (dns => $_->{dns}) : ()),
      ($_->{active} ? () : (archived => 1)),
    }} @ips ] if ($p->{n_ip4} or $p->{n_ip6}) and scalar @ips;

    my @ssids = map { $_->{ssid} } @{ $node->{wireless} || [] };
    $n{ssids} = \@ssids if $p->{n_ssid} and scalar @ssids;

    my ($vendor) = map { $_->{abbrev} } @{ $node->{manufacturer} || [] };
    $n{vendor} = $vendor if $p->{n_vendor} and defined $vendor;

    $n{netbios} = [ map {{
      domain => $_->{domain}, nbname => $_->{nbname},
      nbuser => $_->{nbuser}, ip => $_->{ip},
    }} @{ $node->{netbios} } ] if $p->{n_netbios} and $node->{netbios};

    return \%n;
}

# The port's own columns, sent when not empty. Plugin and custom field values
# go out only through fields, once their only/no ACL has passed.
my @PORT_FIELDS = qw/descr type name mtu mac speed_admin duplex duplex_admin
  up up_admin stp vlan slave_of error_disable_cause ifindex lastchange_stamp
  native_vlan_name agg_master_up_admin agg_master_up/;

my @NEIGHBOR_FIELDS = qw/remote_ip remote_port remote_type remote_id
  remote_dns neighbor_ip/;

# One port as netdisco-ports.js draws it, empty values left out. Free of
# param() and setting() so xt can drive it; $opt carries p (the request's c_*,
# n_* and p_* options as 0 or 1), mac_format_call, domain_suffix, vlans,
# vlan_limit, extra_cols, cells (port => { name => markup } from ports_cells.tt)
# and device.
sub _port_json {
    my ($row, $opt) = @_;
    my $p = $opt->{p} || {};
    my %c = $row->get_columns;
    my $port = $row->port;
    my %j = (port => $port);

    foreach my $key (@PORT_FIELDS) {
        $j{$key} = $c{$key} if defined $c{$key} and length $c{$key};
    }
    foreach my $key (qw/is_master has_subinterfaces/) {
        $j{$key} = 1 if $c{$key};
    }
    $j{is_free} = 1 if $row->has_column_loaded('is_free') and $c{is_free};
    $j{speed} = $row->{speed_running}
      if defined $row->{speed_running} and length $row->{speed_running};
    $j{tags} = [ sort @{ $row->{filtered_tags} } ]
      if $p->{c_tags} and scalar @{ $row->{filtered_tags} || [] };

    # the browser folds subinterfaces from the p_fold options
    $j{group} = $row->{subinterface_group}
      if defined $row->{subinterface_group};
    $j{has_group} = 1 if $row->{has_subinterface_group};
    $j{only_dot_zero} = 1 if $row->{has_only_dot_zero_subinterface};
    $j{is_dot_zero} = 1 if $row->{is_dot_zero_subinterface};

    # vlan_count also feeds the status icon; the names are sent once, in meta
    if (my $v = ($opt->{vlans} || {})->{$port}) {
        $j{vlan_count} = $v->{vlan_count} + 0 if $v->{vlan_count};
        $j{vlans} = [ map { defined $_ ? $_ : '' } @{ $v->{vlan_set} || [] } ]
          if $p->{c_vmember} and $v->{vlan_count}
             and $v->{vlan_count} <= ($opt->{vlan_limit} || 0);
    }

    $j{comment} = $row->{port_comment}
      if $p->{c_comment} and length ($row->{port_comment} || '');
    $j{ssids} = $row->{port_ssids}
      if $p->{c_ssid} and scalar @{ $row->{port_ssids} || [] };
    if ($p->{c_power} and my $power = $row->{port_power}) {
        $j{power} = { map {( $_ => $power->{$_} )}
          grep { defined $power->{$_} } qw/admin power status/ };
    }

    if ($p->{c_nac_summary}
        and ($c{pae_authconfig_port_status} or $c{pae_authconfig_state})) {
        my %nac = ();
        $nac{port_status} = $c{pae_authconfig_port_status}
          if $c{pae_authconfig_port_status};
        $nac{state} = $c{pae_authconfig_state} if $c{pae_authconfig_state};
        $nac{mab} = 1 if $c{pae_authsess_mab};
        my $user = _format_mac($c{pae_authsess_user}, $opt->{mac_format_call});
        if (not defined $user) {
            $user = $c{pae_authsess_user};
            $user =~ s/$opt->{domain_suffix}//g
              if defined $user and defined $opt->{domain_suffix};
        }
        $nac{user} = $user if defined $user and length $user;
        $j{nac} = \%nac;
    }

    if ($p->{c_neighbors}) {
        foreach my $key (@NEIGHBOR_FIELDS) {
            $j{$key} = $c{$key} if defined $c{$key} and length $c{$key};
        }
        foreach my $key (qw/is_uplink manual_topo remote_is_wap remote_is_phone
                            remote_is_discoverable/) {
            $j{$key} = 1 if $c{$key};
        }
        if (defined $c{neighbor_dns} and length $c{neighbor_dns}) {
            ($j{neighbor_dns} = $c{neighbor_dns}) =~ s/$opt->{domain_suffix}//g;
            delete $j{neighbor_dns} unless length $j{neighbor_dns};
        }
        $j{neighbor_mac} = _format_mac($row->{neighbor_net_mac},
          $opt->{mac_format_call}) if $row->{neighbor_net_mac};
        if ($p->{n_inventory}) {
            my $inventory = $row->remote_inventory;
            $j{remote_inventory} = $inventory
              if defined $inventory and length $inventory;
        }
    }
    elsif ($p->{c_nodes}) {
        # the nodes cell still starts under the neighbor
        $j{remote_ip} = $c{remote_ip} if $c{remote_ip};
        $j{is_uplink} = 1 if $c{is_uplink};
    }

    if ($p->{c_nodes}) {
        $j{node_count} = ($row->{node_count} || 0) + 0;
        $j{search} = $row->{nodes_search}
          if length ($row->{nodes_search} || '');
        # a port over the threshold has no stitched_nodes, and fetches its own
        $j{nodes} = [ map { _node_json($_, $c{remote_ip}, $opt) }
          @{ $row->{stitched_nodes} } ] if $row->{stitched_nodes};
    }

    if ($p->{c_admin}) {
        $j{acl_service} = 1 if $row->{port_acl_service};
        $j{acl_pvid} = 1 if $row->{port_acl_pvid};
        $j{acl_name} = 1 if $row->{port_acl_name};
    }

    # Plugin and custom field columns: an ACL-hidden cell goes out without its
    # value; one whose template failed is absent from cells, and its field is drawn.
    my $cells = ($opt->{cells} || {})->{$port} || {};
    $j{cells}->{c_links} = $cells->{c_links}
      if $p->{c_links} and exists $cells->{c_links};

    foreach my $config (@{ $opt->{extra_cols} || [] }) {
        my $name = $config->{name};
        if (not permitted_by_acl($row, $config)) {
            $j{hidden_cells}->{$name} = 1;
            next;
        }
        if (exists $cells->{$name}) {
            $j{cells}->{$name} = $cells->{$name};
            next;
        }
        my $field = $config->{field};
        $j{fields}->{$field} = $c{$field}
          if $field and defined $c{$field} and length $c{$field};
        $j{data}->{$name} = $config->{json}->($row, $opt->{device})
          if $config->{renderer} and ref $config->{json} eq 'CODE';
    }

    return \%j;
}

# VLAN number to name, once for the device
sub _vlan_names {
    my ($vlans) = @_;
    my %names = ();
    foreach my $v (values %{ $vlans || {} }) {
        my @set = @{ $v->{vlan_set} || [] };
        my @names = @{ $v->{vlan_name_set} || [] };
        foreach my $i (grep { defined $set[$_] } 0 .. $#set) {
            $names{ $set[$i] } = (defined $names[$i] ? $names[$i] : '');
        }
    }
    return \%names;
}

# What every port shares, sent once beside the rows: the options, thresholds,
# plugin column configs and node_params, the querystring a collapsed port's
# nodes are fetched with.
sub _port_meta {
    my ($in) = @_;
    my $p = $in->{p} || {};
    return {
      device => $in->{device},
      # port links carry the device as asked for
      q => $in->{q},
      params => $p,
      only_free => ($in->{only_free} ? 1 : 0),
      settings => $in->{settings} || {},
      vlan_names => (($p->{p_vlan_names} and $in->{vlans})
        ? _vlan_names($in->{vlans}) : {}),
      extra => { map {( $_->{name} => {
        (defined $_->{field} ? (field => $_->{field}) : ()),
        editable => ($_->{editable} ? 1 : 0),
        ($_->{renderer} ? (renderer => $_->{renderer}) : ()),
      } )} @{ $in->{extra_cols} || [] } },
      node_params => (defined $in->{node_params} ? $in->{node_params} : ''),
    };
}

# The plugin columns with a device_port_column.tt and no renderer of their own
sub _template_columns {
    my ($cols) = @_;
    my $engine = engine('template');
    return [ grep {
      not $_->{renderer}
        and $engine->view("plugin/$_->{name}/device_port_column")
    } @$cols ];
}

# The cells still drawn by Template Toolkit: external links and plugin column
# templates, in one render, handed back by port and column through collect().
# A failed cell is left out, and the browser draws the column's field instead.
sub _template_cells {
    my ($results, $stash, $want_links, $cols) = @_;
    return {} unless $want_links or scalar @$cols;

    my %out = ();
    my $collect = sub {
        my ($port, $name, $html) = @_;
        $html = '' unless defined $html;
        $html =~ s/^\s+|\s+$//g;
        $out{$port}->{$name} = $html;
        return '';
    };

    template 'ajax/device/ports_cells.tt', {
      %$stash,
      results => $results,
      want_links => ($want_links ? 1 : 0),
      cell_cols => $cols,
      collect => $collect,
    }, { layout => 'noop' };

    return \%out;
}

# The table as the browser draws it: columns, one hash per port, and meta
ajax '/ajax/data/device/ports' => require_login sub {
    content_type 'application/json';
    my $data = _port_rows()
      or return to_json { columns => [], rows => [], meta => {} };

    my %p = map {( $_ => (param($_) ? 1 : 0) )}
            grep { m/^[cnp]_/ } keys %{ params() };
    my $results = $data->{results};
    my $device = $data->{device};
    my $vlans = ((ref {} eq ref $data->{vlans}) ? $data->{vlans} : undef);

    # named by the plugin or custom field, so not always c_ like the rest
    my @extra_cols = grep { not $_->{hidden} and param($_->{name}) }
      @{ setting('_extra_device_port_cols') || [] };
    $p{ $_->{name} } = 1 for @extra_cols;

    my $has_ext_links = scalar @{ setting('external_links')->{device_port} || [] };
    my $cells = _template_cells($results, {
        device => $device,
        vlans => $data->{vlans},
        nodes => $data->{nodes_name},
        ips => $data->{ips_name},
      }, ($p{c_links} and $has_ext_links), _template_columns(\@extra_cols));

    my $opt = {
      p => \%p,
      mac_format_call => _mac_format_call(scalar param('mac_format')),
      domain_suffix => setting('domain_suffix'),
      vlans => $vlans,
      vlan_limit => setting('devport_vlan_limit'),
      extra_cols => \@extra_cols,
      cells => $cells,
      device => $device,
    };

    my $port_state = params->{port_state};
    my $meta = _port_meta({
      device => $device->ip,
      q => scalar param('q'),
      p => \%p,
      only_free => ((defined $port_state and not ref $port_state
                     and $port_state eq 'free') ? 1 : 0),
      settings => { map {( $_ => setting($_) )} qw/
        devport_vlan_limit devport_vlans_collapse_threshold
        devport_nodes_collapse_threshold devport_ips_collapse_threshold
        portctl_topology / },
      vlans => $vlans,
      extra_cols => \@extra_cols,
      node_params => $data->{deferred_node_params},
    });

    return to_json {
      columns => _port_columns(\%p, setting('port_columns'), $has_ext_links),
      rows => [ map { _port_json($_, $opt) } @$results ],
      meta => $meta,
    };
};

# one collapsed port's node list, as JSON, fetched when the browser opens it
ajax '/ajax/data/device/port/nodes' => require_login sub {
    content_type 'application/json';
    my $device = schema(vars->{'tenant'})->resultset('Device')
      ->search_for_device(param('q')) or send_error('Bad device', 400);
    my $port = param('port') or send_error('Bad port', 400);
    my $row = $device->ports->find({ port => $port })
      or send_error('Bad port', 400);

    my ($nodes_name, $ips_name, $node_order, $extra_prefetch)
      = _node_display_options();

    _stitch_nodes(schema(vars->{'tenant'}), $device->ip, [$row],
      $nodes_name, $ips_name, $node_order, $extra_prefetch, [$port]);

    my $opt = {
      p => { map {( $_ => (param($_) ? 1 : 0) )}
             qw/n_ip4 n_ip6 n_age n_ssid n_vendor n_netbios/ },
      mac_format_call => _mac_format_call(scalar param('mac_format')),
    };
    return to_json { nodes => [ map { _node_json($_, $row->remote_ip, $opt) }
      @{ $row->{stitched_nodes} } ] };
};

# device ports with a description (er, name) matching
get '/ajax/content/device/ports' => require_login sub {
    # the CSV never reads the neighbor's MAC
    my $data = _port_rows({
      legacy => (request->is_ajax ? _legacy_ports_template() : 0) }) or return;

    if (request->is_ajax) {
        template 'ajax/device/ports.tt', {
          results => $data->{results},
          # kept for site-local template overrides that may still read
          # row.$nodes or row.$ips: site-local template compatibility is
          # a project commitment, even though the shipped template no
          # longer reads them itself
          nodes => $data->{nodes_name},
          ips   => $data->{ips_name},
          device => $data->{device},
          vlans  => $data->{vlans},
          deferred_node_params => $data->{deferred_node_params},
        }, { layout => 'noop' };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/device/ports_csv.tt', {
          results => $data->{results},
          nodes => $data->{nodes_name},
          ips   => $data->{ips_name},
          device => $data->{device},
          vlans  => $data->{vlans},
        }, { layout => 'noop' };
    }
};

# one collapsed port's node list, fetched only when the caller opens it
get '/ajax/content/device/port/nodes' => require_login sub {
    my $device = schema(vars->{'tenant'})->resultset('Device')
      ->search_for_device(param('q')) or send_error('Bad device', 400);
    my $port = param('port') or send_error('Bad port', 400);
    my $row = $device->ports->find({ port => $port })
      or send_error('Bad port', 400);

    my ($nodes_name, $ips_name, $node_order, $extra_prefetch)
      = _node_display_options();

    _stitch_nodes(schema(vars->{'tenant'}), $device->ip, [$row],
      $nodes_name, $ips_name, $node_order, $extra_prefetch, [$port]);

    template 'ajax/device/port_nodes.tt', {
      row => $row, device => $device,
    }, { layout => 'noop' };
};

true;
