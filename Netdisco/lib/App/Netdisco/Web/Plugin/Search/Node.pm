package App::Netdisco::Web::Plugin::Search::Node;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use NetAddr::IP::Lite ':lower';
use Net::MAC ();

use App::Netdisco::Web::Plugin;

register_search_tab({ tag => 'node', label => 'Node' });

# nodes matching the param as an IP or DNS hostname or MAC
ajax '/ajax/content/search/node' => require_login sub {
    my $node = param('q');
    send_error('Missing node', 400) unless $node;
    content_type('text/html');

    my $agenot = param('age_invert') || '0';
    my ( $start, $end ) = param('daterange') =~ /(\d+-\d+-\d+)/gmx;

    my $mac = Net::MAC->new(mac => $node, 'die' => 0, verbose => 0);
    my @active = (param('archived') ? () : (-bool => 'active'));

    my @times = ();
    if ($start and $end) {
        $start = $start . ' 00:00:00';
        $end   = $end   . ' 23:59:59';
        if ($agenot) {
            @times = (-or => [
              time_first => [ { '<', $start }, undef ],
              time_last => { '>', $end },
            ]);
        }
        else {
            @times = (-and => [
              time_first => { '>=', $start },
              time_last  => { '<=', $end },
            ]);
        }
    }

    if (! $mac->get_error) {
        my $sightings = schema('netdisco')->resultset('Node')
          ->search_by_mac({mac => $mac->as_IEEE, @active, @times});

        my $ips = schema('netdisco')->resultset('NodeIp')
          ->search_by_mac({mac => $mac->as_IEEE, @active, @times});

        my $netbios = schema('netdisco')->resultset('NodeNbt')
          ->search_by_mac({mac => $mac->as_IEEE, @active, @times});

        my $ports = schema('netdisco')->resultset('DevicePort')
          ->search({mac => $mac->as_IEEE});

        my $wireless = schema('netdisco')->resultset('NodeWireless')->search(
            { mac => $mac->as_IEEE },
            { order_by   => { '-desc' => 'time_last' },
              '+columns' => [
                {
                  time_last_stamp => \"to_char(time_last, 'YYYY-MM-DD HH24:MI')"
                }]
            }
        );

        return unless $sightings->has_rows
            or $ips->has_rows
            or $ports->has_rows
            or $netbios->has_rows;

        template 'ajax/search/node_by_mac.tt', {
          ips       => $ips,
          sightings => $sightings,
          ports     => $ports,
          wireless  => $wireless,
          netbios   => $netbios,
        }, { layout => undef };
    }
    else {
        my $set;
        my $name = $node;

        if (param('partial')) {
            $name = "\%$name\%" if $name !~ m/%/;
        }

        $set = schema('netdisco')->resultset('NodeNbt')
            ->search_by_name({nbname => $name, @active, @times});

        unless ( $set->has_rows ) {
            if (my $ip = NetAddr::IP::Lite->new($node)) {
                # search_by_ip() will extract cidr notation if necessary
                $set = schema('netdisco')->resultset('NodeIp')
                  ->search_by_ip({ip => $ip, @active, @times});
            }
            else {
                if ($name !~ m/%/ and setting('domain_suffix')) {
                    $name .= setting('domain_suffix')
                        if index($name, setting('domain_suffix')) == -1;
                }

                $set = schema('netdisco')->resultset('NodeIp')
                  ->search_by_dns({dns => $name, @active, @times});

                # if the user selects Vendor search opt, then
                # we'll try the OUI company name as a fallback

                if (not $set->has_rows and param('show_vendor')) {
                    $set = schema('netdisco')->resultset('NodeIp')
                      ->with_times
                      ->search(
                        {'oui.company' => { -ilike => "\%$node\%"}, @times},
                        {'prefetch' => 'oui'},
                      );
                }
            }
        }

        return unless $set and $set->has_rows;
        $set = $set->search_rs({}, { order_by => 'me.mac' });

        template 'ajax/search/node_by_ip.tt', {
          macs => $set,
          archive_filter => {@active},
        }, { layout => undef };
    }
};

true;
