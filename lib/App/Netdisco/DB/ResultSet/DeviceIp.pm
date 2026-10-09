package App::Netdisco::DB::ResultSet::DeviceIp;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

use NetAddr::IP::Lite;

my $AGE = q/replace( date_trunc( 'minute', age( LOCALTIMESTAMP, %s ) ) ::text, 'mon', 'month') AS age/;

# looked up only for the rows returned, not for every candidate row
my $VENDOR = q{COALESCE(me.vendor, CASE WHEN me.node THEN (SELECT m.company FROM manufacturer m}
  . q{ WHERE m.range @> ('x' || lpad(translate(me.mac::text, ':', ''), 16, '0'))::bit(64)::bigint LIMIT 1) END)};

=head1 ADDITIONAL METHODS

=head2 ip_inventory( $subnet, \%opts )

Returns the IP Inventory report rows for C<$subnet> (a L<NetAddr::IP::Lite>):
device interface addresses, node ARP and IPv6 neighbor cache entries, and
NetBIOS entries, one row per IP, plus every unused address in the subnet when
C<never> is set. The query starts from C<device_ip> and unions the node tables
onto it, which is why it lives in this class.

Options: C<never>, C<age_invert>, C<limit>, and C<start> with C<end> (timestamps
as C<YYYY-MM-DD HH:MM:SS>). For an IP with several rows the device's own
active address wins, then an active node, then an inactive node, then a
generated never-seen address; among those, the most recently seen wins.

=cut

sub ip_inventory {
  my ($rs, $subnet, $opts) = @_;
  $opts ||= {};
  my $schema = $rs->result_source->schema;

  my $devices = $rs->search_rs(undef, {
    join   => ['device', 'device_port'],
    select => [
      'alias AS ip', 'device_port.mac as mac', 'creation AS time_first',
      'device.last_discover AS time_last', 'dns', \'true AS active', \'false AS node',
      \(sprintf $AGE, 'device.last_discover'), 'device.vendor', \'null AS nbname',
    ],
    as => [qw( ip mac time_first time_last dns active node age vendor nbname )],
  })->hri;

  my $node_ips = $schema->resultset('NodeIp')->search_rs(undef, {
    join      => ['netbios'],
    columns   => [qw( ip mac time_first time_last dns active )],
    '+select' => [ \'true AS node', \(sprintf $AGE, 'me.time_last'), \'NULL AS vendor', 'netbios.nbname' ],
    '+as'     => [qw( node age vendor nbname )],
  })->hri;

  my $netbios = $schema->resultset('NodeNbt')->search_rs(undef, {
    columns   => [qw( ip mac time_first time_last )],
    '+select' => [ \'null AS dns', 'active', \'true AS node', \(sprintf $AGE, 'time_last'), \'NULL AS vendor', 'nbname' ],
    '+as'     => [qw( dns active node age vendor nbname )],
  })->hri;

  my $union = $devices->union_all([ $node_ips, $netbios ]);

  if ($opts->{never}) {
    $subnet = NetAddr::IP::Lite->new('0.0.0.0/32') if ($subnet->bits ne 32);
    my $unused = $schema->resultset('Virtual::CidrIps')->search_rs(undef, {
      bind    => [ $subnet->cidr ],
      columns => [qw( ip mac time_first time_last dns active node age vendor nbname )],
    })->hri;
    $union = $union->union_all([ $unused ]);
  }

  my $one_per_ip = $union->search_rs({ ip => { '<<' => $subnet->cidr } }, {
    select => [
      \'DISTINCT ON (ip) ip', 'mac', 'dns',
      \q/date_trunc('second', time_last) AS time_last/,
      \q/date_trunc('second', time_first) AS time_first/,
      'active', 'node', 'age', 'vendor', 'nbname',
    ],
    as => [qw( ip mac dns time_last time_first active node age vendor nbname )],
    # a generated never-seen row (active and node both false) must lose to any
    # real binding, even an inactive one, or a seen address reads as never seen
    order_by => [ {-asc => 'ip'},
                  \'CASE WHEN active AND NOT node THEN 0 WHEN active THEN 1 WHEN node THEN 2 ELSE 3 END',
                  \'time_last DESC NULLS LAST', {-asc => 'dns'}, {-asc => 'mac'} ],
  })->as_query;

  my $when = undef;
  if ($opts->{start} and $opts->{end}) {
    $when = $opts->{age_invert}
      ? { -or => [ time_first => [ undef ],
                   time_last  => [ { '<', $opts->{start} }, { '>', $opts->{end} } ] ] }
      : { -or => [ -and => [ time_first => undef, time_last => undef ],
                   -and => [ time_last => { '>=', $opts->{start} },
                             time_last => { '<=', $opts->{end} } ] ] };
  }

  my $order = [ {-desc => 'age'}, {-asc => 'ip'} ];
  my $limited = $union->search_rs($when, { from => { me => $one_per_ip } })
                      ->order_by($order)->limit($opts->{limit} || 256);

  return $union->search_rs(undef, {
    from      => { me => $limited->as_query },
    columns   => [qw( ip mac time_first time_last dns active node age nbname )],
    '+select' => [ \$VENDOR ],
    '+as'     => [ 'vendor' ],
    order_by  => $order,
  })->hri;
}

1;
