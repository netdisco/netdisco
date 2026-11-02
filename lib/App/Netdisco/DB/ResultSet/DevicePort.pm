package App::Netdisco::DB::ResultSet::DevicePort;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

use Try::Tiny;
require Dancer::Logger;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

=head1 ADDITIONAL METHODS

=head2 with_times

This is a modifier for any C<search()> (including the helpers below) which
will add the following additional synthesized columns to the result set:

=over 4

=item lastchange_stamp

=back

=cut

sub with_times {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+columns' => { lastchange_stamp =>
          \("to_char(device.last_discover - (device.uptime - me.lastchange) / 100 * interval '1 second', "
            ."'YYYY-MM-DD HH24:MI:SS')") },
        join => 'device',
      });
}

=head2 with_is_free

This is a modifier for any C<search()> (including the helpers below) which
will add the following additional synthesized columns to the result set:

=over 4

=item is_free

=back

In the C<$cond> hash (the first parameter) pass in the C<age_num> which must
be an integer, and the C<age_unit> which must be a string of either C<days>,
C<weeks>, C<months> or C<years>.

=cut

sub with_is_free {
  my ($rs, $cond, $attrs) = @_;

  my $interval = (delete $cond->{age_num}) .' '. (delete $cond->{age_unit});

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+columns' => { is_free =>
          # NOTE this query is in `git grep 'THREE PLACES'`
          \["me.up_admin = 'up' AND me.up != 'up' AND "
              ."(me.type IS NULL OR me.type !~* '^(53|ieee8023adLag|propVirtual|l2vlan|l3ipvlan|135|136|137)\$') AND "
              ."((age(LOCALTIMESTAMP, to_timestamp(extract(epoch from device.last_discover) - (device.uptime/100))::timestamp) < ?::interval "
              ."AND (last_node.time_last IS NULL OR age(LOCALTIMESTAMP, last_node.time_last) > ?::interval)) "
              ."OR age(LOCALTIMESTAMP, to_timestamp(extract(epoch from device.last_discover) - (device.uptime - me.lastchange)/100)::timestamp) > ?::interval)",
            [{} => $interval],[ {} => $interval],[ {} => $interval]] },
        join => [qw/device last_node/],
      });
}

=head2 only_free_ports

This is a modifier for any C<search()> (including the helpers below) which
will restrict results based on whether the port is considered "free".

In the C<$cond> hash (the first parameter) pass in the C<age_num> which must
be an integer, and the C<age_unit> which must be a string of either C<days>,
C<weeks>, C<months> or C<years>.

=cut

sub only_free_ports {
  my ($rs, $cond, $attrs) = @_;

  my $interval = (delete $cond->{age_num}) .' '. (delete $cond->{age_unit});

  return $rs
    ->search_rs($cond, $attrs)
    ->search(
      {
        # NOTE this query is in `git grep 'THREE PLACES'`
        'me.up_admin' => 'up',
        'me.up'       => { '!=' => 'up' },
        'me.type' => [ '-or' =>
          { '=' => undef },
          { '!~*' => '^(53|ieee8023adLag|propVirtual|l2vlan|l3ipvlan|135|136|137)$' },
        ],
        -or => [
          -and => [
            \["age(LOCALTIMESTAMP, to_timestamp(extract(epoch from device.last_discover) - (device.uptime/100))::timestamp) < ?::interval",
              [{} => $interval]],
            -or => [
              'last_node.time_last' => undef,
              \["age(LOCALTIMESTAMP, last_node.time_last) > ?::interval", [{} => $interval]],
            ]
          ],
          \["age(LOCALTIMESTAMP, to_timestamp(extract(epoch from device.last_discover) - (device.uptime - me.lastchange)/100)::timestamp) > ?::interval",
            [{} => $interval]],
        ],
      },{ join => [qw/device last_node/] },
    );
}

=head2 with_properties

This is a modifier for any C<search()> which
will add the following additional synthesized columns to the result set:

=over 4

=item error_disable_cause

=item remote_is_discoverable (boolean)

=item remote_is_wap (boolean)

=item remote_is_phone (boolean)

=item remote_dns

=item ifindex

=back

=cut

sub with_properties {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+select' => [qw/
          properties.error_disable_cause
          properties.remote_is_discoverable
          properties.remote_is_wap
          properties.remote_is_phone
          properties.remote_dns
          properties.ifindex
          properties.pae_authconfig_port_control
          properties.pae_authconfig_state
          properties.pae_authconfig_port_status
          properties.pae_authsess_user
          properties.pae_authsess_mab
          properties.pae_last_eapol_frame_source
        /],
        '+as' => [qw/
          error_disable_cause
          remote_is_discoverable remote_is_wap remote_is_phone remote_dns
          ifindex 
          pae_authconfig_port_control 
          pae_authconfig_state 
          pae_authconfig_port_status
          pae_authsess_user 
          pae_authsess_mab
          pae_last_eapol_frame_source
        /],
        join => 'properties',
      });
}

=head2 with_remote_inventory

This is a modifier for any C<search()> which
will add the following additional synthesized columns to the result set:

=over 4

=item remote_vendor

=item remote_model

=item remote_os_ver

=item remote_serial

=back

=cut

sub with_remote_inventory {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+select' => [qw/
          properties.remote_vendor
          properties.remote_model
          properties.remote_os_ver
          properties.remote_serial
        /],
        '+as' => [qw/
          remote_vendor remote_model remote_os_ver remote_serial
        /],
        join => 'properties',
      });
}

=head2 with_vlan_count

This is a modifier for any C<search()> (including the helpers below) which
will add the following additional synthesized columns to the result set:

=over 4

=item vlan_count

=back

=cut

sub with_vlan_count {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+columns' => { vlan_count =>
          $rs->result_source->schema->resultset('DevicePortVlan')
            ->search(
              {
                'dpv.ip'   => { -ident => 'me.ip' },
                'dpv.port' => { -ident => 'me.port' },
              },
              { alias => 'dpv' }
            )->count_rs->as_query
        },
      });
}

=head1 SPECIAL METHODS

=head2 delete( \%options? )

Overrides the built-in L<DBIx::Class> delete method to more efficiently
handle the removal or archiving of nodes. Deleting a subset of a device's
ports removes per-port rows and nodes only for those ports.

=cut

sub _plural { (shift || 0) == 1 ? 'entry' : 'entries' };

# Equal counts mean $ports is the whole device, which keeps the cheaper SQL.
sub _is_port_subset {
  my ($self, $ports, @switches) = @_;
  return 0 unless scalar @switches;
  my $device_ports = $self->result_source->schema->resultset('DevicePort')
    ->search({ ip => { '-in' => \@switches } });
  return ($ports->count < $device_ports->count) ? 1 : 0;
}

sub _node_condition {
  my ($self, $ports, $is_subset, @switches) = @_;

  # A whole-device delete keeps the plain switch list: a multi-device delete
  # would otherwise bind every port name of every device.
  return { switch => { '-in' => \@switches } } unless $is_subset;

  my %ports_of;
  push @{ $ports_of{ $_->{ip} } }, $_->{port}
    for $ports->search(undef, {
      columns => [qw/ip port/],
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    })->all;

  # counts and rows are separate statements, so a concurrent commit can leave
  # no rows here. Those ports are gone and own no nodes to delete; an empty
  # -or would drop the WHERE, and the switch list would take every node
  # on the switch, which is the whole-device bug this method avoids.
  return { switch => { '-in' => [] } } unless %ports_of;

  return { -or => [ map { { switch => $_, port => { '-in' => $ports_of{$_} } } }
                        sort keys %ports_of ] };
}

sub delete {
  my $self = shift;

  my $schema = $self->result_source->schema;
  my $ports = $self->search(undef, { columns => 'ip' });

  my $ip = undef;
  {
    no autovivification;
    try { $ip ||= ${ $ports->{attrs}->{where}->{ip}->{'-in'} }->[1]->[1] };
    try { $ip ||= $ports->{attrs}->{where}->{'me.ip'} };
  }
  $ip ||= 'netdisco';

  # a list, not a subquery: given a subquery, PostgreSQL can merge-join
  # through node_pkey instead of using the (switch, port, active) index
  my @switches = $ports->search(undef, { columns => ['ip'], distinct => 1 })
                       ->get_column('ip')->all;
  my $is_subset = $self->_is_port_subset($ports, @switches);

  my $per_port = $is_subset
    ? do {
        my ($sql, @bind) = @{ ${ $self->search(undef, { columns => [qw/ip port/] })->as_query } };
        \[ '(ip, port) IN ' . $sql, @bind ];
      }
    : { '-in' => $ports->as_query };

  foreach my $set (qw/
    DevicePortPower
    DevicePortProperties
    DevicePortSsid
    DevicePortVlan
    DevicePortWireless
  /) {
      my $gone = $schema->resultset($set)->search(
        ($is_subset ? $per_port : { ip => $per_port }),
      )->delete;

      Dancer::Logger::debug( sprintf( ' [%s] db/ports - removed %d port %s from %s',
        $ip, $gone, _plural($gone), $set ) ) if defined Dancer::Logger::logger();
  }

  $schema->resultset('Node')->search(
    $self->_node_condition($ports, $is_subset, @switches),
  )->delete(@_);

  # now let DBIC do its thing
  return $self->next::method();
}

=head2 retire_ports( $device_ip, \@port_names, $mode )

Removes the named ports of one device and returns the number of C<device_port>
rows removed. An empty list returns 0 and sends no SQL. Both modes delete the
rows of the five per-port tables, then the C<device_port> rows, in one
transaction and with plain statements, bypassing the C<delete> override above.
Nodes and C<device_port_log> are always kept. C<$mode> is one of:

=over 4

=item vanished

The ports are no longer reported by the device.

=item ignored

The ports are excluded by configuration.

=back

=cut

my @PER_PORT_SETS = qw/
  DevicePortPower
  DevicePortProperties
  DevicePortSsid
  DevicePortVlan
  DevicePortWireless
/;

sub retire_ports {
  my ($self, $device_ip, $port_names, $mode) = @_;

  die sprintf("retire_ports: mode must be 'vanished' or 'ignored', got '%s'\n",
    (defined $mode ? $mode : 'undef'))
    unless defined $mode and $mode =~ m/^(?:vanished|ignored)$/;
  return 0 unless $port_names and scalar @$port_names;

  return $mode eq 'vanished'
    ? $self->_retire_vanished_ports($device_ip, $port_names)
    : $self->_retire_ignored_ports($device_ip, $port_names);
}

sub _retire_vanished_ports {
  my ($self, $device_ip, $port_names) = @_;
  return $self->_delete_ports_and_properties($device_ip, $port_names);
}

sub _retire_ignored_ports {
  my ($self, $device_ip, $port_names) = @_;
  return $self->_delete_ports_and_properties($device_ip, $port_names);
}

sub _delete_ports_and_properties {
  my ($self, $device_ip, $port_names) = @_;

  my $schema = $self->result_source->schema;
  my @tables = ((map { $schema->source($_)->name } @PER_PORT_SETS),
                $self->result_source->name);
  my $removed = 0;

  $schema->txn_do(sub {
    foreach my $table (@tables) {
      my $gone = $schema->storage->dbh_do(sub {
        my ($storage, $dbh) = @_;
        $dbh->do("DELETE FROM $table WHERE ip = ? AND port = ANY(?)",
          undef, $device_ip, $port_names);
      });
      $removed = $gone + 0 if $table eq $tables[-1];
    }
  });

  return $removed;
}

=head2 order_by_port_name( \@also )

Orders the result set the way the device Ports tab shows ports, using the
C<port_sortkey()> function schema version 99 installs. Any further ordering
terms are passed in C<\@also> and applied after the port name.

The port key has to lead, and this method exists so that only one place knows
it. When connected nodes are prefetched, DBIC collapses the rows into objects
and needs each port's rows contiguous, which a node column sorted ahead of the
port name would break. Passing the node terms here rather than chaining a
second C<order_by> also avoids the other half of that trap: a chained
C<order_by> replaces the previous one rather than appending to it.

The tiebreak on the raw port name is not decoration. C<port_sortkey()>
deliberately ties equivalent names, C<10GigabitEthernet1/1> against
C<GigabitEthernet1/1>, and without a tiebreak the order within a tie is
whatever Postgres happens to return, which is what makes paging unsafe.

Both comparisons are C<COLLATE "C">, matching the JavaScript, which compares
strings by code unit.

=cut

# Checked once per process rather than per query. Steps 98-99 and 101-102 run
# strict, so the function can be missing only if they were forced or replayed
# with --redeploy-all, both of which skip failing statements and stamp the
# version anyway. Without this the first symptom is every Ports tab request
# failing with a bare "function port_sortkey(text) does not exist" from inside
# a query. Deliberately no fallback to the Perl sort_port: that would hide a
# broken deployment behind an order which is not the same one.
my $port_sortkey_present = 0;

sub _assert_port_sortkey {
  my $rs = shift;
  return if $port_sortkey_present;

  my $found = $rs->result_source->schema->storage->dbh_do(sub {
    my (undef, $dbh) = @_;
    my ($exists) = $dbh->selectrow_array(
      q{SELECT to_regprocedure('port_sortkey(text)') IS NOT NULL});
    return $exists;
  });

  die "port_sortkey() is missing from the database, so ports cannot be ordered.\n"
    . "Run netdisco-db-deploy to apply schema version 99. If the database is\n"
    . "already at 99 or later, a step that creates it (98-99 or 101-102) was\n"
    . "forced or replayed with --redeploy-all and the function was skipped:\n"
    . "check the schema_step_forced table and run netdisco-db-deploy --check,\n"
    . "then apply\n"
    . "share/schema_versions/App-Netdisco-DB-98-99-PostgreSQL.sql by hand and\n"
    . "read the error it gives.\n"
      unless $found;

  $port_sortkey_present = 1;
}

sub order_by_port_name {
  my ($rs, $also) = @_;
  $rs->_assert_port_sortkey;

  return $rs->search_rs({}, { order_by => [
    \'port_sortkey(me.port) COLLATE "C"',
    \'me.port COLLATE "C"',
    @{ $also || [] },
  ] });
}

1;
