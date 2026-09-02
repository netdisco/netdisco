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

register_device_tab({ tag => 'ports', label => 'Ports', provides_csv => 1 });

# $nodes_name (see below) names a has_many relation, but the node source it
# reads from differs by name. Kept as a hash, not a chain of regex tests,
# because a fifth combination should be a new row here, not a new branch.
my %node_result_class = (
    nodes                 => 'Node',
    active_nodes          => 'Virtual::ActiveNode',
    nodes_with_age        => 'Virtual::NodeWithAge',
    active_nodes_with_age => 'Virtual::ActiveNodeWithAge',
);

# Fetches nodes for one device and groups them by port name. Split out from
# the route so xt/52-ports-node-stitch.t can call it directly: the route is
# require_login and the xt suite has no session to drive it through.
#
# HashRefInflator returns plain hashrefs, which changes how Template Toolkit
# reads two of the relations it wants to walk: manufacturer (belongs_to) and
# netbios (might_have) come back as a single hashref rather than a blessed
# row, and TT's FOREACH over a bare hashref iterates its key/value pairs
# instead of treating it as one item. Wrapping each in an arrayref restores
# the one-row-or-none shape the template already expects. wireless is
# has_many and arrives as an arrayref already, so it needs no such wrapping.
sub _stitch_nodes {
    my ($schema, $device_ip, $rows, $nodes_name, $ips_name, $node_order, $extra_prefetch) = @_;

    my $node_rs = $schema->resultset($node_result_class{$nodes_name})
      ->search({ switch => $device_ip }, {
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

    # attached here rather than by the caller, so a test calling this
    # function exercises the same key the template reads instead of agreeing
    # with its own copy of the attach line.
    $_->{stitched_nodes} = ($nodes_by_port{ $_->port } || []) for @$rows;
    return;
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

    # what kind of nodes are we interested in?
    my $nodes_name = (param('n_archived') ? 'nodes' : 'active_nodes');
    $nodes_name .= '_with_age' if param('n_age');

    my $ips_name = ((param('n_ip4') and param('n_ip6')) ? 'ips'
                   : param('n_ip4') ? 'ip4s'
                   : 'ip6s');

    # Ordering terms for the node query below, never for $set: see
    # DevicePort's order_by_port_name for why the port key has to lead there,
    # and _stitch_nodes for why these are qualified against the node source
    # instead.
    my @node_order = ();
    my @extra_prefetch = ();

    # row.stitched_nodes is read even when c_nodes is off, to find the
    # neighbor's MAC for the Neighbors column, so the stitch has to run for
    # either.
    if (param('c_nodes') or param('c_neighbors')) {
        # Fetched separately and joined by port name below, not prefetched.
        # One prefetch of ports to nodes to IPs returns the product of the
        # three and DBIC inflates every row of it: 598 ms on a 229 port
        # device where the SQL behind it is 16 ms. A second has_many branch
        # multiplies it again, which is what c_ssid used to do.
        @node_order = (
          \qq{regexp_replace(COALESCE(me.vlan, '0'), '[^0-9]*' ,'0') :: integer},
          'me.mac',
          "${ips_name}.ip",
        );

        # retrieve wireless SSIDs, if asked for
        push @extra_prefetch, 'wireless' if param('n_ssid');

        # retrieve NetBIOS, if asked for
        push @extra_prefetch, 'netbios' if param('n_netbios');

        # retrieve vendor, if asked for
        push @extra_prefetch, 'manufacturer' if param('n_vendor');
    }

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
    # sort_port pass whose result the browser overwrote anyway. @node_order
    # does not belong here any more: it is qualified for the node source, not
    # for $set, which has its own mac and vlan columns that would silently
    # take over the ordering instead.
    $set = $set->order_by_port_name();

    # run query
    my @results = $set->all;

    # fetch and attach nodes by port name; see _stitch_nodes for why this
    # replaced a prefetch
    _stitch_nodes(schema(vars->{'tenant'}), $device->ip, \@results,
      $nodes_name, $ips_name, \@node_order, \@extra_prefetch)
      if (param('c_nodes') or param('c_neighbors'));

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

true;
