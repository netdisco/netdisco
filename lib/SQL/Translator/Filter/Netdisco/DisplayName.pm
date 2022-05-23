package SQL::Translator::Filter::Netdisco::DisplayName;

use strict;
use warnings;

use Scalar::Util 'blessed';
use SQL::Translator::Netdisco::Utils;

sub filter {
    my ($schema, @args) = @_;

    $schema->extra(display_name => make_label($schema->name));

    foreach my $table ($schema->get_tables) {
        $table = $schema->get_table($table)
            if not blessed $table;

        $table->extra(display_name => make_label($table->name));

        foreach my $field ($table->get_fields) {
            $field = $table->get_field($field)
                if not blessed $field;

            # avoid reverse relationships, they should have been named already
            next if $field->extra('is_reverse');

            # must be belongs_to as we already skipped other rel types
            if ($field->extra('rel_type')
                and ($field->extra('fields')->[0] || '') eq $field->name) {

                $field->extra(display_name => make_label($field->extra('ref_table')));
            }
            else {
                $field->extra(display_name => make_label($field->name));
            }
        }
    }
}

1;
