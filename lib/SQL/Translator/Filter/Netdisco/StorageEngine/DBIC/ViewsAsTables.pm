package SQL::Translator::Filter::Netdisco::StorageEngine::DBIC::ViewsAsTables;

# SQLT doesn't provide for proper Field objects in Views
# instead, there is simply an ordered list of field names.
# It's useful to have full objects, for the extra() method
# if nothing else. This Filter creates a Table for each
# View and populates it with Field objects. It should be
# run very early on in the Filter list, if not first.

use strict;
use warnings;

use SQL::Translator::Netdisco::Utils;

sub filter {
    my ($sqlt, @args) = @_;
    my $schema = shift @args;

    foreach my $tbl_name ($schema->sources) {
        my $source = $schema->source($tbl_name);
        my $from = make_path($source);

        if ($source->isa('DBIx::Class::ResultSource::View')) {
            my $tbl = $sqlt->add_table(name => lc $from);
            $tbl->extra(is_read_only => 1);

            foreach my $field ($source->columns) {
                $tbl->add_field(
                    name => lc $field,
                    data_type => 'text',
                );
            }

            $tbl->primary_key($_) for $source->primary_columns;
        }
        else {
            my $tbl = $sqlt->get_table($from);
            $tbl->extra(is_read_only => 1)
                if 0 == scalar $source->primary_columns;
        }
    }
}

1;
