package App::Netdisco::Web::Plugin::Device::Ports;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Util::Web (); # for sort_port
use App::Netdisco::Web::Plugin;

register_device_tab({ tag => 'ports', label => 'Ports' });

# device ports with a description (er, name) matching
ajax '/ajax/content/device/ports' => require_login sub {
    my $q = param('q');

    my $device = schema('netdisco')->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);
    my $set = $device->ports;

    # refine by ports if requested
    my $f = param('f');
    if ($f) {
        if ($f =~ m/^\d+$/) {
            $set = $set->search({
              -or => {
                'me.vlan' => $f,
                'port_vlans_tagged.vlan' => $f,
              },
            }, { join => 'port_vlans_tagged' });
            return unless $set->count;
        }
        else {
            if (param('partial')) {
                # change wildcard chars to SQL
                $f =~ s/\*/%/g;
                $f =~ s/\?/_/g;
                # set wilcards at param boundaries
                $f =~ s/^\%*/%/;
                $f =~ s/\%*$/%/;
                # enable ILIKE op
                $f = { '-ilike' => $f };
            }

            if ($set->search({'me.port' => $f})->count) {
                $set = $set->search({'me.port' => $f});
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

    # make sure query asks for formatted timestamps when needed
    $set = $set->with_times if param('c_lastchange');

    # get number of vlans on the port to control whether to list them or not
    $set = $set->with_vlan_count if param('c_vmember');

    # run single collapsed query for all relations, but only if we're not
    # also fetching archived data (tests show it's better this way)
    $set = $set->search_rs({}, { prefetch => [{ port_vlans_tagged => 'vlan'}] })
      if param('c_vmember') and not (param('c_nodes') and param('n_archived'));

    # what kind of nodes are we interested in?
    my $nodes_name = (param('n_archived') ? 'nodes' : 'active_nodes');
    $nodes_name .= '_with_age' if param('c_nodes') and param('n_age');
    $set = $set->search_rs({}, { order_by => ["${nodes_name}.mac", "ips.ip"] })
      if param('c_nodes');

    # retrieve active/all connected nodes, if asked for
    $set = $set->search_rs({}, { prefetch => [{$nodes_name => 'ips'}] })
      if param('c_nodes');

    # retrieve neighbor devices, if asked for
    $set = $set->search_rs({}, { prefetch => [{neighbor_alias => 'device'}] })
      if param('c_neighbors');

    # sort ports (empty set would be a 'no records' msg)
    my $results = [ sort { &App::Netdisco::Util::Web::sort_port($a->port, $b->port) } $set->all ];
    return unless scalar @$results;

    content_type('text/html');
    template 'ajax/device/ports.tt', {
      results => $results,
      nodes => $nodes_name,
      device => $device,
    }, { layout => undef };
};

true;
