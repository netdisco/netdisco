package Netdisco::DB::ResultSet::DevicePort;
use base 'DBIx::Class::ResultSet';

use strict;
use warnings FATAL => 'all';

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
  $cond  ||= {};
  $attrs ||= {};

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+select' => [
          \"to_char(device.last_discover - (device.uptime - lastchange) / 100 * interval '1 second',
                      'YYYY-MM-DD HH24:MI:SS')",
        ],
        '+as' => [qw/ lastchange_stamp /],
        join => 'device',
      });
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
  $cond  ||= {};
  $attrs ||= {};

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+columns' => { tagged_vlans_count =>
          $rs->result_source->schema->resultset('DevicePortVlanTagged')
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

1;
