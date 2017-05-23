use utf8;
package App::Netdisco::DB::Result::DeviceSkip;

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("device_skip");
__PACKAGE__->add_columns(
  "backend",
  { data_type => "text", is_nullable => 0 },
  "device",
  { data_type => "inet", is_nullable => 0 },
  "action",
  { data_type => "text", is_nullable => 0 },
  "deferrals",
  { data_type => "integer", is_nullable => 1, default_value => '0' },
  "skipover",
  { data_type => "boolean", is_nullable => 1, default_value => \'false' },
);

__PACKAGE__->set_primary_key("backend", "device", "action");

__PACKAGE__->add_unique_constraint(
  device_skip_pkey => [qw/backend device action/]);

=head1 METHODS

=head2 increment_deferrals

Increments the C<deferrals> field in the row, only if the row is in storage.
There is a race in the update, but this is not worrying for now.

=cut

sub increment_deferrals {
  my $row = shift;
  return unless $row->in_storage;
  return $row->update({ deferrals => ($row->deferrals + 1) });
}

1;
