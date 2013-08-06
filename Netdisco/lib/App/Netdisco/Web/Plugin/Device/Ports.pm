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
            $f =~ s/\*/%/g if index($f, '*') >= 0;
            $f =~ s/\?/_/g if index($f, '?') >= 0;
            $f = { '-ilike' => $f };

            if ($set->search({'me.port' => $f})->count) {
                $set = $set->search({'me.port' => $f});
            }
            else {
                $set = $set->search({'me.name' => $f});
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

    # run single collapsed query for all relations, but only if we're not
    # also fetching archived data (tests show it's better this way)
    $set = $set->search_rs({}, { prefetch => [{ port_vlans_tagged => 'vlan'}] })
      if param('c_vmember') and not (param('c_nodes') and param('n_archived'));

    # what kind of nodes are we interested in?
    my $nodes_name = (param('n_archived') ? 'nodes' : 'active_nodes');
    $set = $set->search_rs({}, { order_by => ["${nodes_name}.mac", "ips.ip"] })
      if param('c_nodes');
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
      device => $device,
    }, { layout => undef };
};

true;
