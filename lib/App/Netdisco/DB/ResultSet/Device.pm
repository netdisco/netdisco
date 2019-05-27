package App::Netdisco::DB::ResultSet::Device;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

use Try::Tiny;
use Regexp::Common 'net';
use NetAddr::IP::Lite ':lower';

require Dancer::Logger;

=head1 ADDITIONAL METHODS

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
          since_first_seen    => \"extract(epoch from (age(now(), me.creation)))",
          since_last_discover => \"extract(epoch from (age(now(), me.last_discover)))",
          since_last_macsuck  => \"extract(epoch from (age(now(), me.last_macsuck)))",
          since_last_arpnip   => \"extract(epoch from (age(now(), me.last_arpnip)))",
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
    my $by_ip = ($q =~ m{^(?:$RE{net}{IPv4}|$RE{net}{IPv6})$}i) ? 1 : 0;

    my $clause;
    if ($by_ip) {
        my $ip = NetAddr::IP::Lite->new($q)
          or return undef; # could be a MAC address!
        $clause = [
            'me.ip'  => { '<<=' => $ip->cidr },
            'device_ips.alias' => { '<<=' => $ip->cidr },
        ];
    }
    else {
        $q = "\%$q\%" if ($options->{partial} and $q !~ m/\%/);
        $clause = [
            'me.name' => { '-ilike' => $q },
            'me.dns'  => { '-ilike' => $q },
            'device_ips.dns' => { '-ilike' => $q },
        ];
    }

    return $rs->search(
      {
        -or => $clause,
      },
      {
        order_by => [qw/ me.dns me.ip /],
        join => 'device_ips',
        distinct => 1,
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

=item model

Will match exactly the C<model> field.

=item os

Will match exactly the C<os> field, which is the operating sytem.

=item os_ver

Will match exactly the C<os_ver> field, which is the operating sytem software version.

=item vendor

Will match exactly the C<vendor> (manufacturer).

=item dns

Can match any of the Device IP address aliases as a substring.

=item ip

Can be a string IP or a NetAddr::IP object, either way being treated as an
IPv4 or IPv6 prefix within which the device must have one IP address alias.

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
    my @layer_search = ( '_', '_', '_', '_', '_', '_', '_' );
    # @layer_search is computer indexed, left->right
    my $layers = $p->{layers};
    if ( defined $layers && ref $layers ) {
      foreach my $layer (@$layers) {
        next unless defined $layer and length($layer);
        next if ( $layer < 1 || $layer > 7 );
        $layer_search[ $layer - 1 ] = 1;
      }
    }
    elsif ( defined $layers ) {
      $layer_search[ $layers - 1 ] = 1;
    }
    # the database field is in order 87654321
    my $layer_string = join( '', reverse @layer_search );

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
          ($p->{layers} ? ('me.layers' =>
            { '-ilike' => "\%$layer_string" }) : ()),

          ($p->{model} ? ('me.model' =>
            { '-in' => $p->{model} }) : ()),
          ($p->{os} ? ('me.os' =>
            { '-in' => $p->{os} }) : ()),
          ($p->{os_ver} ? ('me.os_ver' =>
            { '-in' => $p->{os_ver} }) : ()),
          ($p->{vendor} ? ('me.vendor' =>
            { '-in' => $p->{vendor} }) : ()),

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
        (($p->{dns} or $p->{ip}) ? (
          join => 'device_ips',
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

=item module serials (exact)

=item location

=item name

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
        'device_ips.alias::text' => { '-ilike' => $q },
    ];

    # but also allow prefix search
    if (my $ip = NetAddr::IP::Lite->new($qc)) {
        $ip_clause = [
            'me.ip'  => { '<<=' => $ip->cidr },
            'device_ips.alias' => { '<<=' => $ip->cidr },
        ];
    }

    return $rs->search(
      {
        -or => [
          'me.contact'  => { '-ilike' => $q },
          'me.serial'   => { '-ilike' => $q },
          'me.location' => { '-ilike' => $q },
          'me.name'     => { '-ilike' => $q },
          'me.description' => { '-ilike' => $q },
          'me.ip' => { '-in' =>
            $rs->search({ 'modules.serial' => $qc },
                        { join => 'modules', columns => 'ip' })->as_query()
          },
          -or => [
            'me.dns'      => { '-ilike' => $q },
            'device_ips.dns' => { '-ilike' => $q },
          ],
          -or => $ip_clause,
        ],
      },
      {
        order_by => [qw/ me.dns me.ip /],
        join => 'device_ips',
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

Related rows from the C<device_vlan> table will be prefetched.

=back

=cut

sub carrying_vlan {
    my ($rs, $cond, $attrs) = @_;

    die "vlan number required for carrying_vlan\n"
      if ref {} ne ref $cond or !exists $cond->{vlan};

    return $rs
      ->search_rs({ 'vlans.vlan' => $cond->{vlan} },
        {
          order_by => [qw/ me.dns me.ip /],
            columns  => [
                'me.ip',     'me.dns',
                'me.model',  'me.os',
                'me.vendor', 'vlans.vlan',
                'vlans.description'
            ],
            join => 'vlans'
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

Related rows from the C<device_vlan> table will be prefetched.

=back

=cut

sub carrying_vlan_name {
    my ($rs, $cond, $attrs) = @_;

    die "vlan name required for carrying_vlan_name\n"
      if ref {} ne ref $cond or !exists $cond->{name};

    $cond->{'vlans.description'} = { '-ilike' => delete $cond->{name} };

    return $rs
      ->search_rs({}, {
        order_by => [qw/ me.dns me.ip /],
          columns  => [
              'me.ip',     'me.dns',
              'me.model',  'me.os',
              'me.vendor', 'vlans.vlan',
              'vlans.description'
          ],
          join => 'vlans'
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
                  'dp.type' => { '!=' => 'propVirtual' },
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
  $ip ||= 'netdisco';

  foreach my $set (qw/
    DeviceIp
    DeviceVlan
    DevicePower
    DeviceModule
    Community
  /) {
      my $gone = $schema->resultset($set)->search(
        { ip => { '-in' => $devices->as_query } },
      )->delete;

      Dancer::Logger::debug sprintf ' [%s] db/device - removed %d %s from %s',
        $ip, $gone, _plural($gone), $set if defined Dancer::Logger::logger();
  }

  foreach my $set (qw/
    Admin
    DeviceSkip
  /) {
      $schema->resultset($set)->search(
        { device => { '-in' => $devices->as_query } },
      )->delete;
  }

  my $gone = $schema->resultset('Topology')->search({
    -or => [
      { dev1 => { '-in' => $devices->as_query } },
      { dev2 => { '-in' => $devices->as_query } },
    ],
  })->delete;

  Dancer::Logger::debug sprintf ' [%s] db/device - removed %d manual topology %s',
    $ip, $gone, _plural($gone) if defined Dancer::Logger::logger();

  $schema->resultset('DevicePort')->search(
    { ip => { '-in' => $devices->as_query } },
  )->delete(@_);

  # now let DBIC do its thing
  return $self->next::method();
}

1;
