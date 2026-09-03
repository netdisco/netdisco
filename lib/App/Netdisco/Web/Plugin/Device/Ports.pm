package App::Netdisco::Web::Plugin::Device::Ports;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Util::Permission 'acl_matches';
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
# The neighbors-only branch is the shipped default, c_neighbors being checked
# in config.yml and c_nodes not. It reads node data only to name the MAC
# behind a port's remote_ip, so it fetches nothing when no port carries one,
# and only those ports when some do.
#
# Returns undef to fetch nothing, or an arrayref for $only_ports: empty means
# the whole device, non-empty scopes the fetch to those ports.
sub _node_fetch_scope {
    my ($want_nodes, $want_neighbors, $rows) = @_;

    return [] if $want_nodes;
    return undef if not $want_neighbors;

    my @neighbor_ports = map { $_->port } grep { $_->remote_ip } @$rows;
    return undef if not scalar @neighbor_ports;
    return \@neighbor_ports;
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

# Ports at or under the threshold get their own row fetched; a port over it
# still gets one when it might carry a neighbor's own MAC, since the
# Neighbors column reads stitched_nodes for that regardless of the node
# list's own threshold, but only under c_neighbors: that carve-out is what
# makes neighbor_mac renderable at all, and stitching every node of an
# over-threshold trunk port just to throw the render away is expensive on
# exactly the ports a core switch has the most of. Kept free of param() and
# setting() so xt can pin the decision without a session.
sub _threshold_scope {
    my ($threshold, $want_neighbors, $count_by_port, $rows) = @_;
    return [ map { $_->port }
      grep { ($count_by_port->{ $_->port } || 0) <= $threshold
             or ($want_neighbors and $_->remote_ip) } @$rows ];
}

# device ports with a description (er, name) matching
get '/ajax/content/device/ports' => require_login sub {
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
    # of ports to nodes to IPs returns the product of the three and DBIC
    # inflates every row of it, and a second has_many branch multiplies it
    # again.
    my ($nodes_name, $ips_name, $node_order, $extra_prefetch)
      = _node_display_options();

    # retrieve SSID, if asked for
    $set = $set->search({}, { prefetch => 'ssid' })
      if param('c_ssid');

    # retrieve PoE info, if asked for
    $set = $set->search({}, { prefetch => 'power' })
      if param('c_power');

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

    # fetch and attach nodes by port name, rather than prefetching them
    my $node_fetch_scope = _node_fetch_scope(
      scalar param('c_nodes'), scalar param('c_neighbors'), \@results);

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
              scalar param('c_neighbors'), $count_by_port, \@results);
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

    if (request->is_ajax) {
        template 'ajax/device/ports.tt', {
          results => \@results,
          nodes => $nodes_name,
          ips   => $ips_name,
          device => $device,
          vlans  => $vlans,
          deferred_node_params => $deferred_node_params,
        }, { layout => 'noop' };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/device/ports_csv.tt', {
          results => \@results,
          nodes => $nodes_name,
          ips   => $ips_name,
          device => $device,
          vlans  => $vlans,
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
      nodes => $nodes_name, ips => $ips_name,
    }, { layout => 'noop' };
};

true;
