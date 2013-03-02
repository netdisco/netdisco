package App::Netdisco::Web::Plugin::Search::Node;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use NetAddr::IP::Lite ':lower';
use Net::MAC ();

use App::Netdisco::Web::Plugin;

register_search_tab({ id => 'node', label => 'Node' });

# nodes matching the param as an IP or DNS hostname or MAC
ajax '/ajax/content/search/node' => sub {
    my $node = param('q');
    return unless $node;
    content_type('text/html');

    my $mac = Net::MAC->new(mac => $node, 'die' => 0, verbose => 0);
    my @active = (param('archived') ? () : (-bool => 'active'));

    if (! $mac->get_error) {
        my $sightings = schema('netdisco')->resultset('Node')
          ->search_by_mac({mac => $mac->as_IEEE, @active});

        my $ips = schema('netdisco')->resultset('NodeIp')
          ->search_by_mac({mac => $mac->as_IEEE, @active});

        my $ports = schema('netdisco')->resultset('DevicePort')
          ->search({mac => $mac->as_IEEE});

        return unless $sightings->count
            or $ips->count
            or $ports->count;

        template 'ajax/search/node_by_mac.tt', {
          ips => $ips,
          sightings => $sightings,
          ports => $ports,
        }, { layout => undef };
    }
    else {
        my $set;

        if (my $ip = NetAddr::IP::Lite->new($node)) {
            # search_by_ip() will extract cidr notation if necessary
            $set = schema('netdisco')->resultset('NodeIp')
              ->search_by_ip({ip => $ip, @active});
        }
        else {
            if (param('partial')) {
                $node = "\%$node\%" if $node !~ m/%/;
            }
            elsif (setting('domain_suffix')) {
                $node .= setting('domain_suffix')
                    if index($node, setting('domain_suffix')) == -1;
            }
            $set = schema('netdisco')->resultset('NodeIp')
              ->search_by_dns({dns => $node, @active});
        }
        return unless $set and $set->count;

        template 'ajax/search/node_by_ip.tt', {
          macs => $set,
          archive_filter => {@active},
        }, { layout => undef };
    }
};

true;
