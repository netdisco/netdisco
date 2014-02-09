package App::Netdisco::DB::ResultSet;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';

__PACKAGE__->load_components(
    qw{Helper::ResultSet::SetOperations Helper::ResultSet::Shortcut});

=head2 get_distinct_col( $column )

Returns an asciibetical sorted list of the distinct values in the given column
of the Device table. This is useful for web forms when you want to provide a
drop-down list of possible options.

=cut

sub get_distinct_col {
  my ($rs, $col) = @_;
  return $rs unless $col;

  return $rs->search({},
    {
      columns => [$col],
      order_by => $col,
      distinct => 1
    }
  )->get_column($col)->all;
}

1;
