use utf8;
package App::Netdisco::DB::Result::DeviceSkip;

use strict;
use warnings;

use List::MoreUtils ();

use base 'DBIx::Class::Core';
__PACKAGE__->table("device_skip");
__PACKAGE__->add_columns(
  "backend",
  { data_type => "text", is_nullable => 0 },
  "device",
  { data_type => "inet", is_nullable => 0 },
  "actionset",
  { data_type => "text[]", is_nullable => 1, default_value => \"'{}'::text[]" },
  "deferrals",
  { data_type => "integer", is_nullable => 1, default_value => '0' },
  "last_defer",
  { data_type => "timestamp", is_nullable => 1 },
);

__PACKAGE__->set_primary_key("backend", "device");

__PACKAGE__->add_unique_constraint(
  device_skip_pkey => [qw/backend device/]);

=head1 METHODS

=head2 increment_deferrals

Increments the C<deferrals> field in the row, only if the row is in storage.
There is a race in the update, but this is not worrying for now.

=cut

sub increment_deferrals {
  my $row = shift;
  return unless $row->in_storage;
  return $row->update({
    deferrals => (($row->deferrals || 0) + 1),
    last_defer => \'now()',
  });
}

=head2 add_to_actionset

=cut

sub add_to_actionset {
  my ($row, @badactions) = @_;
  return unless $row->in_storage;
  return unless scalar @badactions;
  return $row->update({ actionset =>
    [ sort (List::MoreUtils::uniq( @{ $row->actionset || [] }, @badactions )) ]
  });
}

1;
