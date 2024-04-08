package App::Netdisco::Web::Plugin::Search::Node;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use NetAddr::IP::Lite ':lower';
use Regexp::Common 'net';
use NetAddr::MAC ();
use POSIX qw/strftime/;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::DNS 'ipv4_from_hostname';
use App::Netdisco::Util::Web 'sql_match';

register_search_tab({
    tag => 'node',
    label => 'Node',
    api_endpoint => 1,
    api_parameters => [
      q => {
        description => 'MAC Address or IP Address or Hostname (without Domain Suffix) of a Node (supports SQL or "*" wildcards)',
        required => 1,
      },
      partial => {
        description => 'Partially match the "q" parameter (wildcard characters not required)',
        type => 'boolean',
        default => 'false',
      },
      deviceports => {
        description => 'MAC Address search will include Device Port MACs',
        type => 'boolean',
        default => 'true',
      },
      show_vendor => {
        description => 'Include interface Vendor in results',
        type => 'boolean',
        default => 'false',
      },
      archived => {
        description => 'Include archived records in results',
        type => 'boolean',
        default => 'false',
      },
      daterange => {
        description => 'Date Range in format "YYYY-MM-DD to YYYY-MM-DD"',
        default => ('1970-01-01 to '. strftime('%Y-%m-%d', gmtime)),
      },
      age_invert => {
        description => 'Results should NOT be within daterange',
        type => 'boolean',
        default => 'false',
      },
      # mac_format is used only in the template (will be IEEE) in results
      #mac_format => {
      #},
      # stamps param is used only in the template (they will be included)
      #stamps => {
      #},
    ],
});

# nodes matching the param as an IP or DNS hostname or MAC
get '/ajax/content/search/node' => require_login sub {
    my $node = param('q');
    send_error('Missing node', 400) unless $node;
    return unless ($node =~ m/\w/); # need some alphanum at least
    content_type('text/html');

    my $agenot = param('age_invert') || '0';
    my ( $start, $end ) = param('daterange') =~ m/(\d+-\d+-\d+)/gmx;

    my $mac = NetAddr::MAC->new(mac => ($node || ''));
    undef $mac if
      ($mac and $mac->as_ieee
      and (($mac->as_ieee eq '00:00:00:00:00:00')
        or ($mac->as_ieee !~ m/^$RE{net}{MAC}$/i)));

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

    my $sightings = schema(vars->{'tenant'})->resultset('Node')
      ->search({-and => [@where_mac, @active, @times]}, {
          order_by => {'-desc' => 'time_last'},
          '+columns' => [
            'device.dns',
            'device.name',
            { time_first_stamp => \"to_char(time_first, 'YYYY-MM-DD HH24:MI')" },
            { time_last_stamp =>  \"to_char(time_last, 'YYYY-MM-DD HH24:MI')" },
          ],
          join => 'device',
      });

    my $ips = schema(vars->{'tenant'})->resultset('NodeIp')
      ->search({-and => [@where_mac, @active, @times]}, {
          order_by => {'-desc' => 'time_last'},
          '+columns' => [
            'manufacturer.company',
            'manufacturer.abbrev',
            { time_first_stamp => \"to_char(time_first, 'YYYY-MM-DD HH24:MI')" },
            { time_last_stamp =>  \"to_char(time_last, 'YYYY-MM-DD HH24:MI')" },
          ],
          join => 'manufacturer'
      })->with_router;

    my $netbios = schema(vars->{'tenant'})->resultset('NodeNbt')
      ->search({-and => [@where_mac, @active, @times]}, {
          order_by => {'-desc' => 'time_last'},
          '+columns' => [
            'manufacturer.company',
            'manufacturer.abbrev',
            { time_first_stamp => \"to_char(time_first, 'YYYY-MM-DD HH24:MI')" },
            { time_last_stamp =>  \"to_char(time_last, 'YYYY-MM-DD HH24:MI')" },
          ],
          join => 'manufacturer'
      });

    my $wireless = schema(vars->{'tenant'})->resultset('NodeWireless')->search(
        { -and => [@where_mac, @wifitimes] },
        { order_by   => { '-desc' => 'time_last' },
          '+columns' => [
            'manufacturer.company',
            'manufacturer.abbrev',
            {
              time_last_stamp => \"to_char(time_last, 'YYYY-MM-DD HH24:MI')"
            }],
          join => 'manufacturer'
        }
    );

    my $rs_dp = schema(vars->{'tenant'})->resultset('DevicePort');
    if ($sightings->has_rows or $ips->has_rows or $netbios->has_rows) {
        my $ports = param('deviceports')
          ? $rs_dp->search({ -and => [@where_mac] }, { order_by => { '-desc' => 'creation' }}) : undef;

        return template 'ajax/search/node_by_mac.tt', {
          ips       => $ips,
          sightings => $sightings,
          ports     => $ports,
          wireless  => $wireless,
          netbios   => $netbios,
        }, { layout => 'noop' };
    }
    else {
        my $ports = param('deviceports')
          ? $rs_dp->search({ -and => [@where_mac, @porttimes] }, { order_by => { '-desc' => 'creation' }}) : undef;

        if (defined $ports and $ports->has_rows) {
            return template 'ajax/search/node_by_mac.tt', {
              ips       => $ips,
              sightings => $sightings,
              ports     => $ports,
              wireless  => $wireless,
              netbios   => $netbios,
            }, { layout => 'noop' };
        }
    }

    my $have_rows = 0;
    my $set = schema(vars->{'tenant'})->resultset('NodeNbt')
        ->search_by_name({nbname => $likeval, @active, @times});
    ++$have_rows if $set->has_rows;

    unless ( $have_rows ) {
        if ($node =~ m{^(?:$RE{net}{IPv4}|$RE{net}{IPv6})(?:/\d+)?$}i
            and my $ip = NetAddr::IP::Lite->new($node)) {

            # search_by_ip() will extract cidr notation if necessary
            $set = schema(vars->{'tenant'})->resultset('NodeIp')->with_router
              ->search_by_ip({ip => $ip, @active, @times});
            ++$have_rows if $set->has_rows;
        }
        else {
            $set = schema(vars->{'tenant'})->resultset('NodeIp')
              ->search_by_dns({
                  ($using_wildcards ? (dns => $likeval) :
                                      (dns => "${likeval}.\%", suffix => setting('domain_suffix'))),
                  @active,
                  @times,
                });
            ++$have_rows if $set->has_rows;

            # try DNS lookup as fallback
            if (not $using_wildcards and not $have_rows) {
                my $resolved_ip = ipv4_from_hostname($node);

                if ($resolved_ip) {
                    $set = schema(vars->{'tenant'})->resultset('NodeIp')
                      ->search_by_ip({ip => $resolved_ip, @active, @times});
                    ++$have_rows if $set->has_rows;
                }
            }

            # if the user selects Vendor search opt, then
            # we'll try the manufacturer company name as a fallback

            if (param('show_vendor') and not $have_rows) {
                $set = schema(vars->{'tenant'})->resultset('NodeIp')
                  ->with_times
                  ->search(
                    {'manufacturer.company' => { -ilike => ''.sql_match($node)}, @times},
                    {'prefetch' => 'manufacturer'},
                  );
                ++$have_rows if $set->has_rows;
            }
        }
    }

    return unless $set and ($have_rows or $set->has_rows);
    $set = $set->search_rs({}, { order_by => 'me.mac' });

    return template 'ajax/search/node_by_ip.tt', {
      macs => $set,
      archive_filter => {@active},
    }, { layout => 'noop' };
};

true;
