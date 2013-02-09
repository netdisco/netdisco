package App::Netdisco::Web::Plugin::Device::Ports;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use App::Netdisco::Util::Web (); # for sort_port

use App::Netdisco::Web::Plugin;

register_device_tab({ id => 'ports', label => 'Ports' });

# device ports with a description (er, name) matching
ajax '/ajax/content/device/ports' => sub {
    my $ip = param('q');
    return unless $ip;

    my $set = schema('netdisco')->resultset('DevicePort')
                ->search({'me.ip' => $ip});

    # refine by ports if requested
    my $q = param('f');
    if ($q) {
        if ($q =~ m/^\d+$/) {
            $set = $set->search({
              -or => {
                'me.vlan' => $q,
                'port_vlans_tagged.vlan' => $q,
              },
            }, { join => 'port_vlans_tagged' });
            return unless $set->count;
        }
        else {
            $q =~ s/\*/%/g if index($q, '*') >= 0;
            $q =~ s/\?/_/g if index($q, '?') >= 0;
            $q = { '-ilike' => $q };

            if ($set->search({'me.port' => $q})->count) {
                $set = $set->search({'me.port' => $q});
            }
            else {
                $set = $set->search({'me.name' => $q});
                return unless $set->count;
            }
        }
    }

    # filter for free ports if asked
    my $free_filter = (param('free') ? 'only_free_ports' : 'with_is_free');
    $set = $set->$free_filter({
      age_num => (param('age_num') || 3),
      age_unit => (param('age_unit') || 'months')
    });

    # make sure query asks for formatted timestamps when needed
    $set = $set->with_times if param('c_lastchange');

    # get number of vlans on the port to control whether to list them or not
    $set = $set->with_vlan_count if param('c_vmember');

    # what kind of nodes are we interested in?
    my $nodes_name = (param('n_archived') ? 'nodes' : 'active_nodes');
    $nodes_name .= '_with_age' if param('c_nodes') and param('n_age');

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
      device => $ip,
    }, { layout => undef };
};

true;
