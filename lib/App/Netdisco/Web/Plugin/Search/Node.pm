package App::Netdisco::Web::Plugin::Search::Node;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use NetAddr::IP::Lite ':lower';
use Regexp::Common 'net';
use NetAddr::MAC ();

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::Web 'sql_match';

register_search_tab({ tag => 'node', label => 'Node' });

# nodes matching the param as an IP or DNS hostname or MAC
ajax '/ajax/content/search/node' => require_login sub {
    my $node = param('q');
    send_error('Missing node', 400) unless $node;
    content_type('text/html');

    my $agenot = param('age_invert') || '0';
    my ( $start, $end ) = param('daterange') =~ m/(\d+-\d+-\d+)/gmx;

    my $mac = NetAddr::MAC->new(mac => $node);
    undef $mac if
      ($mac and $mac->as_ieee
      and (($mac->as_ieee eq '00:00:00:00')
        or ($mac->as_ieee !~ m/$RE{net}{MAC}/)));

    my @active = (param('archived') ? () : (-bool => 'active'));
    my (@times, @wifitimes, @porttimes);

    if ( $start and $end ) {
        $start = $start . ' 00:00:00';
        $end   = $end   . ' 23:59:59';

        if ($agenot) {
            @times = (-or => [
              time_first => [ undef ],
              time_last => [ { '<', $start }, { '>', $end } ]
            ]);
            @wifitimes = (-or => [
              time_last => [ undef ],
              time_last => [ { '<', $start }, { '>', $end } ],
            ]);
            @porttimes = (-or => [
              creation => [ undef ],
              creation => [ { '<', $start }, { '>', $end } ]
            ]);
        }
        else {
            @times = (-or => [
              -and => [
                  time_first => undef,
                  time_last  => undef,
              ],
              -and => [
                  time_last => { '>=', $start },
                  time_last => { '<=', $end },
              ],
            ]);
            @wifitimes = (-or => [
              time_last  => undef,
              -and => [
                  time_last => { '>=', $start },
                  time_last => { '<=', $end },
              ],
            ]);
            @porttimes = (-or => [
              creation => undef,
              -and => [
                  creation => { '>=', $start },
                  creation => { '<=', $end },
              ],
            ]);
        }
    }

    my ($likeval, $likeclause) = sql_match($node, not param('partial'));
    my $using_wildcards = (($likeval ne $node) ? 1 : 0);

    my @where_mac =
      ($using_wildcards ? \['me.mac::text ILIKE ?', $likeval]
                        : ((!defined $mac or $mac->errstr) ? \'0=1' : ('me.mac' => $mac->as_ieee)) );

    my $sightings = schema('netdisco')->resultset('Node')
      ->search({-and => [@where_mac, @active, @times]}, {
          order_by => {'-desc' => 'time_last'},
          '+columns' => [
            'device.dns',
            { time_first_stamp => \"to_char(time_first, 'YYYY-MM-DD HH24:MI')" },
            { time_last_stamp =>  \"to_char(time_last, 'YYYY-MM-DD HH24:MI')" },
          ],
          join => 'device',
      });

    my $ips = schema('netdisco')->resultset('NodeIp')
      ->search({-and => [@where_mac, @active, @times]}, {
          order_by => {'-desc' => 'time_last'},
          '+columns' => [
            'oui.company',
            'oui.abbrev',
            { time_first_stamp => \"to_char(time_first, 'YYYY-MM-DD HH24:MI')" },
            { time_last_stamp =>  \"to_char(time_last, 'YYYY-MM-DD HH24:MI')" },
          ],
          join => 'oui'
      });

    my $netbios = schema('netdisco')->resultset('NodeNbt')
      ->search({-and => [@where_mac, @active, @times]}, {
          order_by => {'-desc' => 'time_last'},
          '+columns' => [
            'oui.company',
            'oui.abbrev',
            { time_first_stamp => \"to_char(time_first, 'YYYY-MM-DD HH24:MI')" },
            { time_last_stamp =>  \"to_char(time_last, 'YYYY-MM-DD HH24:MI')" },
          ],
          join => 'oui'
      });

    my $wireless = schema('netdisco')->resultset('NodeWireless')->search(
        { -and => [@where_mac, @wifitimes] },
        { order_by   => { '-desc' => 'time_last' },
          '+columns' => [
            'oui.company',
            'oui.abbrev',
            {
              time_last_stamp => \"to_char(time_last, 'YYYY-MM-DD HH24:MI')"
            }],
          join => 'oui'
        }
    );

    my $rs_dp = schema('netdisco')->resultset('DevicePort');
    if ($sightings->has_rows or $ips->has_rows or $netbios->has_rows) {
        my $ports = param('deviceports')
          ? $rs_dp->search({ -and => [@where_mac] }) : undef;

        return template 'ajax/search/node_by_mac.tt', {
          ips       => $ips,
          sightings => $sightings,
          ports     => $ports,
          wireless  => $wireless,
          netbios   => $netbios,
        }, { layout => undef };
    }
    else {
        my $ports = param('deviceports')
          ? $rs_dp->search({ -and => [@where_mac, @porttimes] }) : undef;

        if (defined $ports and $ports->has_rows) {
            return template 'ajax/search/node_by_mac.tt', {
              ips       => $ips,
              sightings => $sightings,
              ports     => $ports,
              wireless  => $wireless,
              netbios   => $netbios,
            }, { layout => undef };
        }
    }

    my $set = schema('netdisco')->resultset('NodeNbt')
        ->search_by_name({nbname => $likeval, @active, @times});

    unless ( $set->has_rows ) {
        if (my $ip = NetAddr::IP::Lite->new($node)) {
            # search_by_ip() will extract cidr notation if necessary
            $set = schema('netdisco')->resultset('NodeIp')
              ->search_by_ip({ip => $ip, @active, @times});
        }
        else {
            $likeval .= setting('domain_suffix')
              if index($node, setting('domain_suffix')) == -1;

            $set = schema('netdisco')->resultset('NodeIp')
              ->search_by_dns({dns => $likeval, @active, @times});

            # if the user selects Vendor search opt, then
            # we'll try the OUI company name as a fallback

            if (param('show_vendor') and not $set->has_rows) {
                $set = schema('netdisco')->resultset('NodeIp')
                  ->with_times
                  ->search(
                    {'oui.company' => { -ilike => ''.sql_match($node)}, @times},
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
};

true;
