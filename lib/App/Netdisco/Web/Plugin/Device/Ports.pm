package App::Netdisco::Web::Plugin::Device::Ports;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Util::Permission 'acl_matches';
use App::Netdisco::Util::Port qw/port_acl_service port_acl_pvid port_acl_name/;
use App::Netdisco::Util::Web (); # for sort_port
use App::Netdisco::Web::Plugin;

use List::MoreUtils 'singleton';

register_device_tab({ tag => 'ports', label => 'Ports', provides_csv => 1 });

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

    if (param('c_nodes')) {
        # retrieve active/all connected nodes, if asked for
        $set = $set->search({}, { prefetch => [{$nodes_name => $ips_name}] });
        $set = $set->search({}, { order_by => ["${nodes_name}.vlan", "${nodes_name}.mac", "${ips_name}.ip"] });

        # retrieve wireless SSIDs, if asked for
        $set = $set->search({}, { prefetch => [{$nodes_name => 'wireless'}] })
          if param('n_ssid');

        # retrieve NetBIOS, if asked for
        $set = $set->search({}, { prefetch => [{$nodes_name => 'netbios'}] })
          if param('n_netbios');

        # retrieve vendor, if asked for
        $set = $set->search({}, { prefetch => [{$nodes_name => 'manufacturer'}] })
          if param('n_vendor');
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

    # run query
    my @results = $set->all;

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
    my $subinterfaces_match = (setting('subinterfaces_match') || qr/(.+)\.\d+/i);

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

    foreach my $parent (keys %port_subinterface_count) {
        my $parent_port = [grep {$_->port eq $parent} @results]->[0];
        $parent_port->{has_subinterface_group} = true;
        $parent_port->{has_only_dot_zero_subinterface} = true
          if exists $port_has_dot_zero{$parent}
            and $port_subinterface_count{$parent} == 1
            and ($parent_port->type
              and $parent_port->type =~ m/^(?:ethernetCsmacd|ieee8023adLag)$/i);
        if ($parent_port->{has_only_dot_zero_subinterface}) {
            my $dotzero_port = [grep {$_->port eq "${parent}.0"} @results]->[0];
            $dotzero_port->{is_dot_zero_subinterface} = true;
        }
    }

    # sort ports
    @results = sort { &App::Netdisco::Util::Web::sort_port($a->port, $b->port) } @results;

    # add acl on port config
    if (param('c_admin') and user_has_role('port_control')) {
      # for native vlan change
      map {$_->{port_acl_pvid} = port_acl_pvid($_, $device, logged_in_user)} @results;
      # for name/descr change
      map {$_->{port_acl_name} = port_acl_name($_, $device, logged_in_user)} @results;
      # for up/down and poe
      map {$_->{port_acl_service} = port_acl_service($_, $device, logged_in_user)} @results;
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
