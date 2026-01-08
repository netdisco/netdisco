package App::Netdisco::DB::ResultSet::Device;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

use Try::Tiny;
use Regexp::Common 'net';
use NetAddr::IP::Lite ':lower';
use NetAddr::MAC ();

require Dancer::Logger;

=head1 ADDITIONAL METHODS

=head2 device_ips_with_address_or_name( $address_or_name )

Returns a correlated subquery for the set of C<device_ip> entries for each
device. The IP alias or dns matches the supplied C<address_or_name>, using
C<ILIKE>.

=cut

sub device_ips_with_address_or_name {
  my ($rs, $q, $ipbind) = @_;
  $q ||= '255.255.255.255/32';

  return $rs->search(undef,{
    # NOTE: bind param list order is significant
    join => ['device_ips_by_address_or_name'],
    bind => [$q, $ipbind, $q],
  });
}

=head2 with_module_serials

Adds the C<module_serials.serial> field to the results using
C<module_serials> relation.

=cut

sub with_module_serials {
  my $rs = shift;
  return $rs->search(undef, {
    join => 'module_serials',
    '+columns' => [ qw/ module_serials.ip module_serials.index module_serials.serial / ],
    collapse => 1,
    distinct => 0,
  });
}

=head2 ports_with_mac( $mac )

Returns a correlated subquery for the set of C<device_port> entries for each
device. The port MAC address matches the supplied C<mac>, using C<ILIKE>.

=cut

sub ports_with_mac {
  my ($rs, $mac) = @_;
  $mac ||= '00:00:00:00:00:00';

  return $rs->search(undef,{
    # NOTE: bind param list order is significant
    join => ['ports_by_mac'],
    bind => [$mac],
  });
}

=head2 with_times

This is a modifier for any C<search()> (including the helpers below) which
will add the following additional synthesized columns to the result set:

=over 4

=item uptime_age

=item first_seen_stamp

=item last_discover_stamp

=item last_macsuck_stamp

=item last_arpnip_stamp

=item since_first_seen

=item since_last_discover

=item since_last_macsuck

=item since_last_arpnip

=back

=cut

sub with_times {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+columns' => {
          uptime_age => \("replace(age(timestamp 'epoch' + me.uptime / 100 * interval '1 second', "
            ."timestamp '1970-01-01 00:00:00-00')::text, 'mon', 'month')"),
          first_seen_stamp    => \"to_char(me.creation, 'YYYY-MM-DD HH24:MI')",
          last_discover_stamp => \"to_char(me.last_discover, 'YYYY-MM-DD HH24:MI')",
          last_macsuck_stamp  => \"to_char(me.last_macsuck,  'YYYY-MM-DD HH24:MI')",
          last_arpnip_stamp   => \"to_char(me.last_arpnip,   'YYYY-MM-DD HH24:MI')",
          since_first_seen    => \"extract(epoch from (age(LOCALTIMESTAMP, me.creation)))",
          since_last_discover => \"extract(epoch from (age(LOCALTIMESTAMP, me.last_discover)))",
          since_last_macsuck  => \"extract(epoch from (age(LOCALTIMESTAMP, me.last_macsuck)))",
          since_last_arpnip   => \"extract(epoch from (age(LOCALTIMESTAMP, me.last_arpnip)))",
        },
      });
}

=head2 search_aliases( {$name or $ip or $prefix}, \%options? )

Tries to find devices in Netdisco which have an identity corresponding to
C<$name>, C<$ip> or C<$prefix>.

The search is across all aliases of the device, as well as its "root IP"
identity. Note that this search will try B<not> to use DNS, in case the current
name for an IP does not correspond to the data within Netdisco.

Passing a zero value to the C<partial> key of the C<options> hashref will
prevent partial matching of a host name. Otherwise the default is to perform
a partial, case-insensitive search on the host name fields.

=cut

sub search_aliases {
    my ($rs, $q, $options) = @_;
    $q ||= '255.255.255.255'; # hack to return empty resultset on error
    $options ||= {};
    $options->{partial} = 1 if !defined $options->{partial};

    # rough approximation of IP addresses (v4 in v6 not supported).
    # this helps us avoid triggering any DNS.
    my $by_ip = ($q =~ m{^(?:$RE{net}{IPv4}|$RE{net}{IPv6})(?:/\d+)?$}i) ? 1 : 0;

    my ($clause, $sorter);
    if ($by_ip) {
        my $ip = NetAddr::IP::Lite->new($q)
          or return undef; # could be a MAC address!
        $clause = [
            'me.ip'  => { '<<=' => $ip->cidr },
            'device_ips.alias' => { '<<=' => $ip->cidr },
        ];
        $sorter = \[q{CASE WHEN (me.ip <<= ?) THEN 1 ELSE 0 END}, $ip->cidr];
    }
    else {
        $q = "\%$q\%" if ($options->{partial} and $q !~ m/\%/);
        $clause = [
            'me.name' => { '-ilike' => $q },
            'me.dns'  => { '-ilike' => $q },
            'device_ips.dns' => { '-ilike' => $q },
        ];
        $sorter = \[q{CASE WHEN (me.name ILIKE ? OR me.dns ILIKE ?) THEN 1 ELSE 0 END}, $q, $q];
    }

    return $rs->search(
      {
        -or => $clause,
      },
      {
        '+select' => [ { coalesce => $sorter, -as => 'in_device' } ],
        order_by => [{ -desc => 'in_device' }, { -asc => [qw/ me.dns me.ip /] } ],
        group_by => ['me.ip'],
        join => 'device_ips',
      }
    );
}

=head2 search_for_device( $name or $ip or $prefix )

This is a wrapper for C<search_aliases> which:

=over 4

=item *

Disables partial matching on host names

=item *

Returns only the first result of any found devices

=back

If no matching devices are found, C<undef> is returned.

=cut

sub search_for_device {
    my ($rs, $q, $options) = @_;
    $options ||= {};
    $options->{partial} = 0;
    return $rs->search_aliases($q, $options)->first();
}

=head2 search_by_field( \%cond, \%attrs? )

This variant of the standard C<search()> method returns a ResultSet of Device
entries. It is written to support web forms which accept fields that match and
locate Devices in the database.

The hashref parameter should contain fields from the Device table which will
be intelligently used in a search query.

In addition, you can provide the key C<matchall> which, given a True or False
value, controls whether fields must all match or whether any can match, to
select a row.

Supported keys:

=over 4

=item matchall

If a True value, fields must all match to return a given row of the Device
table, otherwise any field matching will cause the row to be included in
results.

=item name

Can match the C<name> field as a substring.

=item location

Can match the C<location> field as a substring.

=item description

Can match the C<description> field as a substring (usually this field contains
a description of the vendor operating system).

=item mac

Will match exactly the C<mac> field of the Device or any of its Interfaces.

=item model

Will match exactly the C<model> field.

=item os

Will match exactly the C<os> field, which is the operating system.

=item os_ver

Will match exactly the C<os_ver> field, which is the operating system software version.

=item vendor

Will match exactly the C<vendor> (manufacturer).

=item dns

Can match any of the Device IP address aliases as a substring.

=item ip

Can be a string IP or a NetAddr::IP object, either way being treated as an
IPv4 or IPv6 prefix within which the device must have one IP address alias.

=item layers

OSI Layers which the device must support.

=back

=cut

sub search_by_field {
    my ($rs, $p, $attrs) = @_;

    die "condition parameter to search_by_field must be hashref\n"
      if ref {} ne ref $p or 0 == scalar keys %$p;

    my $op = $p->{matchall} ? '-and' : '-or';

    # this is a bit of an inelegant trick to catch junk data entry,
    # whilst avoiding returning *all* entries in the table
    if ($p->{ip} and 'NetAddr::IP::Lite' ne ref $p->{ip}) {
      $p->{ip} = ( NetAddr::IP::Lite->new($p->{ip})
        || NetAddr::IP::Lite->new('255.255.255.255') );
    }

    # For Search on Layers
    my $layers = $p->{layers};
    my @layer_select = ();
    if ( defined $layers && ref $layers ) {
      foreach my $layer (@$layers) {
        next unless defined $layer and length($layer);
        next if ( $layer < 1 || $layer > 7 );
        push @layer_select,
          \[ 'substring(me.layers,9-?, 1)::int = 1', $layer ];
      }
    }
    elsif ( defined $layers ) {
      push @layer_select,
        \[ 'substring(me.layers,9-?, 1)::int = 1', $layers ];
    }

    # get IEEE MAC format
    my $mac = NetAddr::MAC->new(mac => ($p->{mac} || ''));
    undef $mac if
      ($mac and $mac->as_ieee
      and (($mac->as_ieee eq '00:00:00:00:00:00')
        or ($mac->as_ieee !~ m/^$RE{net}{MAC}$/i)));

    my @joins = (
      ($mac ? qw/ports/ : ()),
      (($p->{dns} or $p->{ip}) ? qw/device_ips/ : ()),
    );

    return $rs
      ->search_rs({}, $attrs)
      ->search({
        $op => [
          ($p->{name} ? ('me.name' =>
            { '-ilike' => "\%$p->{name}\%" }) : ()),
          ($p->{location} ? ('me.location' =>
            { '-ilike' => "\%$p->{location}\%" }) : ()),
          ($p->{description} ? ('me.description' =>
            { '-ilike' => "\%$p->{description}\%" }) : ()),

          ($mac ? (
            -or => [
              'me.mac' => $mac->as_ieee,
              'ports.mac' => $mac->as_ieee,
            ]) : ()),

          ($p->{model} ? ('me.model' =>
            { '-in' => $p->{model} }) : ()),
          ($p->{os} ? ('me.os' =>
            { '-in' => $p->{os} }) : ()),
          ($p->{os_ver} ? ('me.os_ver' =>
            { '-in' => $p->{os_ver} }) : ()),
          ($p->{vendor} ? ('me.vendor' =>
            { '-in' => $p->{vendor} }) : ()),

          ($p->{layers} ? (-or => \@layer_select) : ()),

          ($p->{dns} ? (
            -or => [
              'me.dns' => { '-ilike' => "\%$p->{dns}\%" },
              'device_ips.dns' => { '-ilike' => "\%$p->{dns}\%" },
            ]) : ()),

          ($p->{ip} ? (
            -or => [
              'me.ip' => { '<<=' => $p->{ip}->cidr },
              'device_ips.alias' => { '<<=' => $p->{ip}->cidr },
            ]) : ()),
        ],
      },
      {
        order_by => [qw/ me.dns me.ip /],
        ((scalar @joins) ? (
          join => \@joins,
          distinct => 1,
        ) : ()),
      }
    );
}

=head2 search_fuzzy( $value )

This method accepts a single parameter only and returns a ResultSet of rows
from the Device table where one field matches the passed parameter.

The following fields are inspected for a match:

=over 4

=item contact

=item serial

=item chassis_id

=item module serials (exact)

=item location

=item name

=item mac (including port addresses)

=item description

=item dns

=item ip (including aliases)

=back

=cut

sub search_fuzzy {
    my ($rs, $q) = @_;

    die "missing param to search_fuzzy\n"
      unless $q;
    $q = "\%$q\%" if $q !~ m/\%/;
    (my $qc = $q) =~ s/\%//g;

    # basic IP check is a string match
    my $ip_clause = [
        'me.ip::text'  => { '-ilike' => $q },
        'device_ips_by_address_or_name.alias::text' => { '-ilike' => $q },
    ];
    my $ipbind = '255.255.255.255/32';

    # but also allow prefix search
    if ($qc =~ m{^(?:$RE{net}{IPv4}|$RE{net}{IPv6})(?:/\d+)?$}i
        and my $ip = NetAddr::IP::Lite->new($qc)) {

        $ip_clause = [
            'me.ip'  => { '<<=' => $ip->cidr },
            'device_ips_by_address_or_name.alias' => { '<<=' => $ip->cidr },
        ];
        $ipbind = $ip->cidr;
    }

    # get IEEE MAC format
    my $mac = NetAddr::MAC->new(mac => ($q || ''));
    undef $mac if
      ($mac and $mac->as_ieee
      and (($mac->as_ieee eq '00:00:00:00:00:00')
        or ($mac->as_ieee !~ m/^$RE{net}{MAC}$/i)));
    $mac = ($mac ? $mac->as_ieee : $q);

    return $rs->ports_with_mac($mac)
              ->device_ips_with_address_or_name($q, $ipbind)
              ->search(
      {
        -or => [
          'me.contact'     => { '-ilike' => $q },
          'me.serial'      => { '-ilike' => $q },
          'me.chassis_id'  => { '-ilike' => $q },
          'me.location'    => { '-ilike' => $q },
          'me.name'        => { '-ilike' => $q },
          'me.description' => { '-ilike' => $q },
          'me.ip' => { '-in' =>
            $rs->search({ 'modules.serial' => $qc },
                        { join => 'modules', columns => 'ip' })->as_query()
          },
          -or => [
            'me.mac::text' => { '-ilike' => $mac},
            'ports_by_mac.mac::text' => { '-ilike' => $mac},
          ],
          -or => [
            'me.dns'      => { '-ilike' => $q },
            'device_ips_by_address_or_name.dns' => { '-ilike' => $q },
          ],
          -or => $ip_clause,
        ],
      },
      {
        order_by => [qw/ me.dns me.ip /],
        distinct => 1,
      }
    );
}

=head2 carrying_vlan( \%cond, \%attrs? )

 my $set = $rs->carrying_vlan({ vlan => 123 });

Like C<search()>, this returns a ResultSet of matching rows from the Device
table.

The returned devices each are aware of the given Vlan.

=over 4

=item *

The C<cond> parameter must be a hashref containing a key C<vlan> with
the value to search for.

=item *

Results are ordered by the Device DNS and IP fields.

=item *

Column C<pcount> gives a count of the number of ports on the device
that are actually configured to carry the VLAN.

=back

=cut

sub carrying_vlan {
    my ($rs, $cond, $attrs) = @_;

    die "vlan number required for carrying_vlan\n"
      if ref {} ne ref $cond or !exists $cond->{vlan};

    return $rs unless $cond->{vlan};

    return $rs
      ->search_rs({ 'vlans.vlan' => $cond->{vlan} },
        {
          order_by => [qw/ me.dns me.ip /],
          select => [{ count => 'ports.vlan' }],
          as => ['pcount'],
          columns  => [
              'me.ip',     'me.dns',
              'me.model',  'me.os',
              'me.vendor', 'vlans.vlan',
              'vlans.description'
          ],
          join => {'vlans' => 'ports'},
          distinct => 1,
        })
      ->search({}, $attrs);
}

=head2 carrying_vlan_name( \%cond, \%attrs? )

 my $set = $rs->carrying_vlan_name({ name => 'Branch Office' });

Like C<search()>, this returns a ResultSet of matching rows from the Device
table.

The returned devices each are aware of the named Vlan.

=over 4

=item *

The C<cond> parameter must be a hashref containing a key C<name> with
the value to search for. The value may optionally include SQL wildcard
characters.

=item *

Results are ordered by the Device DNS and IP fields.

=item *

Column C<pcount> gives a count of the number of ports on the device
that are actually configured to carry the VLAN.

=back

=cut

sub carrying_vlan_name {
    my ($rs, $cond, $attrs) = @_;

    die "vlan name required for carrying_vlan_name\n"
      if ref {} ne ref $cond or !exists $cond->{name};

    $cond->{'vlans.vlan'} = { '>' => 0 };
    $cond->{'vlans.description'} = { '-ilike' => delete $cond->{name} };

    return $rs
      ->search_rs({}, {
        order_by => [qw/ me.dns me.ip /],
        select => [{ count => 'ports.vlan' }],
        as => ['pcount'],
        columns  => [
            'me.ip',     'me.dns',
            'me.model',  'me.os',
            'me.vendor', 'vlans.vlan',
            'vlans.description'
        ],
        join => {'vlans' => 'ports'},
        distinct => 1,
      })
      ->search($cond, $attrs);
}

=head2 has_layer( $layer )

 my $rset = $rs->has_layer(3);

This predefined C<search()> returns a ResultSet of matching rows from the
Device table of devices advertising support of the supplied layer in the
OSI Model.

=over 4

=item *

The C<layer> parameter must be an integer between 1 and 7.

=cut

sub has_layer {
    my ( $rs, $layer ) = @_;

    die "layer required and must be between 1 and 7\n"
        if !$layer || $layer < 1 || $layer > 7;

    return $rs->search_rs( \[ 'substring(layers,9-?, 1)::int = 1', $layer ] );
}

=back

=head2 get_platforms

Returns a sorted list of Device models with the following columns only:

=over 4

=item vendor

=item model

=item count

=back

Where C<count> is the number of instances of that Vendor's Model in the
Netdisco database.

=cut

sub get_platforms {
  my $rs = shift;
  return $rs->search({}, {
    'columns' => [ 'vendor', 'model' ],
    '+select' => [{ count => 'ip' }],
    '+as' => ['count'],
    group_by => [qw/vendor model/],
    order_by => [{-asc => 'vendor'}, {-asc => 'model'}],
  });
}

=head2 get_releases

Returns a sorted list of Device OS releases with the following columns only:

=over 4

=item os

=item os_ver

=item count

=back

Where C<count> is the number of devices running that OS release in the
Netdisco database.

=cut

sub get_releases {
  my $rs = shift;
  return $rs->search({}, {
    columns => ['os', 'os_ver'],
    '+select' => [ { count => 'ip' } ],
    '+as' => [qw/count/],
    group_by => [qw/os os_ver/],
    order_by => [{-asc => 'os'}, {-asc => 'os_ver'}],
  })

}

=head2 with_layer_features

This is a modifier for any C<search()> which
will add the following additional synthesized columns to the result set:

=over 4

=item is_discoverable

=item is_macsuckable

=item is_arpnipable

=back

=cut

sub with_layer_features {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+columns' => {
          is_discoverable =>
            $rs->result_source->schema->resultset('DeviceSkip')
              ->search(
                { 'ds.device' => { -ident => 'me.ip' }, '-not' => \q{'discover' = ANY(actionset)} },
                { alias => 'ds' },
              )->count_rs->as_query,
          is_macsuckable =>
            $rs->result_source->schema->resultset('DeviceSkip')
              ->search(
                { 'ds.device' => { -ident => 'me.ip' }, '-not' => \q{'macsuck' = ANY(actionset)} },
                { alias => 'ds' },
              )->count_rs->as_query,
          is_arpnipable =>
            $rs->result_source->schema->resultset('DeviceSkip')
              ->search(
                { 'ds.device' => { -ident => 'me.ip' }, '-not' => \q{'arpnip' = ANY(actionset)} },
                { alias => 'ds' },
              )->count_rs->as_query,
        },
      });
}

=head2 with_port_count

This is a modifier for any C<search()> which
will add the following additional synthesized column to the result set:

=over 4

=item port_count

=back

=cut

sub with_port_count {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+columns' => {
          port_count =>
            $rs->result_source->schema->resultset('DevicePort')
              ->search(
                {
                  'dp.ip' => { -ident => 'me.ip' },
                  'dp.type' => [ '-or' =>
                    { '=' => undef },
                    { '!~*' => '^(53|ieee8023adLag|propVirtual|l2vlan|l3ipvlan|135|136|137)$' },
                  ],
                },
                { alias => 'dp' }
              )->count_rs->as_query,
        },
      });
}

=head1 SPECIAL METHODS

=head2 delete( \%options? )

Overrides the built-in L<DBIx::Class> delete method to more efficiently
handle the removal or archiving of nodes.

=cut

sub _plural { (shift || 0) == 1 ? 'entry' : 'entries' };

sub delete {
  my $self = shift;

  my $schema = $self->result_source->schema;
  my $devices = $self->search(undef, { columns => 'ip' });

  my $ip = undef;
  {
    no autovivification;
    try { $ip ||= $devices->{attrs}->{where}->{ip} };
    try { $ip ||= $devices->{attrs}->{where}->{'me.ip'} };
  }
  $ip = ((ref {} eq ref $ip) ? [%$ip]->[1] : $ip);
  $ip ||= 'netdisco';

  foreach my $set (qw/
    Community
    DeviceBrowser
    DeviceIp
    DeviceModule
    DevicePower
    DeviceVlan
  /) {
      my $gone = $schema->resultset($set)->search(
        { ip => { '-in' => $devices->as_query } },
      )->delete;

      Dancer::Logger::debug( sprintf( ' [%s] db/device - removed %d %s from %s',
        $ip, $gone, _plural($gone), $set ) ) if defined Dancer::Logger::logger();
  }

  $schema->resultset('Admin')->search({
    device => { '-in' => $devices->as_query },
  })->delete;

  $schema->resultset('DeviceSkip')->search(
    { device => { '-in' => $devices->as_query } },
  )->delete;

  my $gone = $schema->resultset('Topology')->search({
    -or => [
      { dev1 => { '-in' => $devices->as_query } },
      { dev2 => { '-in' => $devices->as_query } },
    ],
  })->delete;

  Dancer::Logger::debug( sprintf( ' [%s] db/device - removed %d manual topology %s',
    $ip, $gone, _plural($gone) ) ) if defined Dancer::Logger::logger();

  $schema->resultset('DevicePort')->search(
    { ip => { '-in' => $devices->as_query } },
  )->delete(@_);

  # now let DBIC do its thing
  return $self->next::method();
}

1;

__END__
list of tables in the db that use the device:

# use 'ip' as PK
community
device_browser
device_ip
device_module
device_power
device_vlan

# use 'device' as PK
admin
device_skip
topology

# special to let nodes be kept
device_port

# defer to port resultset class
device_port_power
device_port_properties
device_port_ssid
device_port_vlan
device_port_wireless
device_port_log

# dbic does this one itself
device

