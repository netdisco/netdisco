package App::Netdisco::DB::ResultSet::DevicePort;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings FATAL => 'all';

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
          \("to_char(device.last_discover - (device.uptime - lastchange) / 100 * interval '1 second', "
            ."'YYYY-MM-DD HH24:MI:SS')") },
        join => 'device',
      });
}

=head2 with_free_ports

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
          \["up != 'up' and "
              ."age(now(), to_timestamp(extract(epoch from device.last_discover) "
                ."- (device.uptime - lastchange)/100)) "
              ."> ?::interval",
            [{} => $interval]] },
        join => 'device',
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
        'up' => { '!=' => 'up' },
      },{
        where =>
          \["age(now(), to_timestamp(extract(epoch from device.last_discover) "
                ."- (device.uptime - lastchange)/100)) "
              ."> ?::interval",
            [{} => $interval]],
      join => 'device' },
    );
}

=head2 with_vlan_count

This is a modifier for any C<search()> (including the helpers below) which
will add the following additional synthesized columns to the result set:

=over 4

=item tagged_vlans_count

=back

=cut

sub with_vlan_count {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+columns' => { tagged_vlans_count =>
          $rs->result_source->schema->resultset('Virtual::DevicePortVlanTagged')
            ->search(
              {
                'dpvt.ip' => { -ident => 'me.ip' },
                'dpvt.port' => { -ident => 'me.port' },
              },
              { alias => 'dpvt' }
            )->count_rs->as_query
        },
      });
}

=head1 SPECIAL METHODS

=head2 delete( \%options? )

Overrides the built-in L<DBIx::Class> delete method to more efficiently
handle the removal or archiving of nodes.

=cut

sub delete {
  my $self = shift;

  my $schema = $self->result_source->schema;
  my $ports = $self->search(undef, { columns => 'ip' });

  foreach my $set (qw/
    DevicePortPower
    DevicePortVlan
    DevicePortWireless
    DevicePortSsid
    DevicePortLog
  /) {
      $schema->resultset($set)->search(
        { ip => { '-in' => $ports->as_query }},
      )->delete;
  }

  $schema->resultset('Node')->search(
    { switch => { '-in' => $ports->as_query }},
  )->delete(@_);

  # now let DBIC do its thing
  return $self->next::method();
}

1;
