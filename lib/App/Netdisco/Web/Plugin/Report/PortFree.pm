package App::Netdisco::Web::Plugin::Report::PortFree;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

use NetAddr::IP::Lite ':lower';
use Regexp::Common 'net';

register_report(
    {   category     => 'Port',
        tag          => 'portfree',
        label        => 'Free Ports',
        provides_csv => 1,
        api_endpoint => 1,
        api_parameters => [
          age_num => {
            description => 'Free for at least (quantity), see free_since',
            type => 'integer',
            default => '30',
          },
          age_unit => {
            description => 'Free for at least (period), see free_since',
            enum => [qw/days weeks months years/],
            default => 'days',
          },
          up => {
            description => 'Operational status',
            enum => [qw/down up any/],
            default => 'down',
          },
          up_admin => {
            description => 'Administrative status',
            enum => [qw/any up down/],
            default => 'any',
          },
          device => {
            description => 'Device IP or prefix, or start of DNS name or SNMP name',
          },
          basis => {
            description => 'Only ports whose free_since is based on these, comma separated (default all)',
            enum => [qw/mac lastchange boot unknown/],
          },
          limit => {
            description => 'Return at most this many ports, longest free first, unknown last (default all)',
            type => 'integer',
          },
        ],
    }
);

# same exclusion as only_free_ports and Virtual::PortUtilization
my $virtual_types = '^(53|ieee8023adLag|propVirtual|l2vlan|l3ipvlan|135|136|137)$';

my $stamp = q{'YYYY-MM-DD HH24:MI:SS'};

my $lastchange = q{device.last_discover - (device.uptime - me.lastchange) / 100 * interval '1 second'};
# discover already corrects uptime for 32-bit wraps
my $boot = q{device.last_discover - device.uptime / 100 * interval '1 second'};

# Where free_since comes from. The last MAC seen when there is one. Without
# it, a port that is down has been down since its last change, and when that
# change is within minutes of boot it only says "at least since boot". A port
# that is up without a MAC says nothing about being free.
my $basis = qq{CASE
  WHEN last_node.time_last IS NOT NULL THEN 'mac'
  WHEN me.up = 'up' OR ($lastchange) IS NULL THEN NULL
  WHEN ($lastchange) <= ($boot) + interval '10 minutes' THEN 'boot'
  ELSE 'lastchange' END};
my $free_since = qq{CASE
  WHEN last_node.time_last IS NOT NULL THEN last_node.time_last
  WHEN me.up = 'up' THEN NULL
  ELSE $lastchange END};

get '/ajax/content/report/portfree' => require_login sub {
    my $age_num  = param('age_num');
    $age_num = 30 unless defined $age_num and $age_num =~ m/^\d+$/;
    my $age_unit = param('age_unit') || 'days';
    $age_unit = 'days' unless $age_unit =~ m/^(?:days|weeks|months|years)$/;
    my $interval = "$age_num $age_unit";

    # the sidebar sends its own default, the API has none so a bulk consumer
    # gets every port
    my $limit = param('limit');
    $limit = 0 unless defined $limit and $limit =~ m/^\d+$/;

    # the sidebar submits one value per ticked box, the API also takes a
    # comma separated list; none, or all four, means no filter
    my $basis_param = param('basis');
    my %want = map { $_ => 1 }
      grep { m/^(?:mac|lastchange|boot|unknown)$/ }
      map { split m/,/ } (ref $basis_param ? @$basis_param
                          : defined $basis_param ? ($basis_param) : ());
    my @basis_clause = ();
    if (scalar keys %want and scalar keys %want < 4) {
        my @known = grep { $_ ne 'unknown' } sort keys %want;
        push @basis_clause, { -or => [
          (@known ? \[ "($basis) IN (". join(',', ('?') x @known) .')', @known ] : ()),
          ($want{unknown} ? \"($basis) IS NULL" : ()),
        ] };
    }

    my $up       = param('up') || 'down';
    my $up_admin = param('up_admin') || 'any';

    my @device_clause = ();
    if (my $q = param('device')) {
        if ($q =~ m{^(?:$RE{net}{IPv4}|$RE{net}{IPv6})(?:/\d+)?$}i
            and my $ip = NetAddr::IP::Lite->new($q)) {
            @device_clause = (\[ 'me.ip <<= ?::inet', $ip->cidr ]);
        }
        else {
            $q = "$q\%" if $q !~ m/\%/;
            @device_clause = ({ -or => [
              'device.dns'  => { -ilike => $q },
              'device.name' => { -ilike => $q },
            ] });
        }
    }

    my @results = schema(vars->{'tenant'})->resultset('DevicePort')->search(
        {   'me.type' => [ '-or' =>
              { '=' => undef },
              { '!~*' => $virtual_types },
            ],
            # a neighbor seen by CDP/LLDP means the port is in use, MAC or not
            'me.remote_ip' => undef,
            'me.remote_id' => undef,
            ($up eq 'any' ? ()
              : ('me.up' => ($up eq 'up' ? 'up' : { '!=' => 'up' }))),
            ($up_admin eq 'any' ? ()
              : ('me.up_admin' => ($up_admin eq 'up' ? 'up' : { '!=' => 'up' }))),
            # archived nodes count too: last_node is over the whole node table,
            # so "no MAC" means none since the node was expired. A port whose
            # free_since is unknown is kept, as nothing says it is in use.
            -and => [
              { -or => [
                \"($free_since) IS NULL",
                \[ "age(LOCALTIMESTAMP, $free_since) >= ?::interval", $interval ],
              ] },
              @device_clause,
              @basis_clause,
            ],
        },
        {   join     => [qw/device last_node/],
            columns  => [qw/ip port name type vlan speed up_admin up/],
            '+columns' => [
              { dns          => 'device.dns' },
              { device_name  => 'device.name' },
              { last_mac     => 'last_node.mac' },
              { last_mac_seen => \"to_char(last_node.time_last, $stamp)" },
              { days_since_mac =>
                  \'floor(extract(epoch from (LOCALTIMESTAMP - last_node.time_last)) / 86400)::int' },
              { lastchange_stamp => \"to_char($lastchange, $stamp)" },
              { last_macsuck  => \"to_char(device.last_macsuck, $stamp)" },
              { last_discover => \"to_char(device.last_discover, $stamp)" },
              { device_boot   => \"to_char($boot, $stamp)" },
              { free_since    => \"to_char($free_since, $stamp)" },
              { free_since_basis => \$basis },
              { days_free =>
                  \"floor(extract(epoch from (LOCALTIMESTAMP - ($free_since))) / 86400)::int" },
            ],
            order_by => [ \"($free_since) ASC NULLS LAST", qw/me.ip me.port/ ],
            ($limit ? (rows => $limit) : ()),
        }
    )->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json (\@results);
        template 'ajax/report/portfree.tt', {
          results => $json,
          truncated => ($limit and scalar @results >= $limit ? $limit : 0),
        }, { layout => 'noop' };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/portfree_csv.tt',
            { results => \@results, }, { layout => 'noop' };
    }
};

1;
