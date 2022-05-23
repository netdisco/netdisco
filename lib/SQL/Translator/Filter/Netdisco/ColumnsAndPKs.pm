package SQL::Translator::Filter::Netdisco::ColumnsAndPKs;

use strict;
use warnings;

# PK can be FK so need to unique fields
use List::MoreUtils 'uniq';

sub filter {
    my ($schema, @args) = @_;

    foreach my $tbl ($schema->get_tables) {
        # add an ordered list of columns, placing PKs first
        $tbl->extra(fields => [
            uniq map {$_->name}
                     (sort grep {$_->is_primary_key} $tbl->get_fields),
                     (sort grep {not $_->is_primary_key and not $_->extra('is_reverse')
                                 and not $_->is_foreign_key} $tbl->get_fields),
                     (sort grep {$_->is_foreign_key and not $_->extra('is_reverse')
                                 and not $_->extra('masked_by')} $tbl->get_fields),
                     (sort grep {$_->extra('is_reverse')
                                 and $_->extra('rel_type') eq 'might_have'} $tbl->get_fields),
                     (sort grep {$_->extra('is_reverse')
                                 and $_->extra('rel_type') eq 'has_many'} $tbl->get_fields),
                     (sort grep {$_->extra('is_reverse')
                                 and $_->extra('rel_type') eq 'many_to_many'} $tbl->get_fields),
        ]);

        # SQLT's primary_key() returns the constraint, not names
        $tbl->extra(pks => [
            sort map  {$_->name}
                 grep {$_->is_primary_key} $tbl->get_fields,
        ]);
    }
}

1;
