package SQL::Translator::Filter::Netdisco::StorageEngine::DBIC::Relationships;

use strict;
use warnings;

use Lingua::EN::Inflect::Number;
use SQL::Translator::Netdisco::Utils;

sub add_to_fields_at {
    my ($table, $data) = @_;
    my $field = {
        name => $data->{name},
        extra => { rel_type => $data->{rel_type} },
        data_type => 'text',
    };

    for (qw/ref_table ref_fields fields via/) {
        $field->{extra}->{$_} = $data->{$_} if exists $data->{$_};
    }

    if ($data->{rel_type} =~ m/_many$/) {
        $field->{extra}->{display_name} =
            make_label(Lingua::EN::Inflect::Number::to_PL($data->{name}));
    }
    else {
        $field->{extra}->{display_name} = make_label($data->{name});
    }

    if ($data->{rel_type} eq 'belongs_to') {
        if (my $f = $table->get_field($field->{name})) {
            # col already exists, so update metadata
            $f->extra($_ => $field->{extra}->{$_})
                for keys %{$field->{extra}};
            $f->{is_foreign_key} = 1;
        }
        else {
            # need to skip subsequent belongs_to where one has
            # already been set - not really ideal but best we can do
            return if
                scalar grep {$table->get_field($_)->extra('ref_table')}
                            @{$field->{extra}->{fields}};

            $table->get_field($_)->extra('masked_by' => $field->{name})
                for @{$field->{extra}->{fields}};
            my $f = $table->add_field(%$field);
            $f->{is_foreign_key} = 1;
        }
    }
    else {
        $field->{extra}->{is_reverse} = 1;
        my $f = $table->add_field(%$field);
        $f->{is_foreign_key} = 1;
    }
}

sub filter {
    my ($sqlt, @args) = @_;
    my $schema = shift @args;
    my $rels = {};

    foreach my $tbl_name ($schema->sources) {
        my $source = $schema->source($tbl_name);
        my $from = make_path($source);
        my $sqlt_tbl = $sqlt->get_table($from)
            or die "mismatched (rel) table name between SQLT and DBIC: [$from, $tbl_name]\n";
        my $new_cols = $rels->{$from} ||= {};

        foreach my $r ($source->relationships) {
            my $rel_info = $source->relationship_info($r);
            my $cond = $rel_info->{cond};
            $new_cols->{$r} = { name => $r };

            # only basic AND type clauses
            if (ref $cond ne ref {}) {
                delete $new_cols->{$r};
                next;
            }

            # catch dangling rels and skip them
            if (not eval{$source->related_source($r)}) {
                delete $new_cols->{$r};
                next;
            }
            $new_cols->{$r}->{ref_table} = make_path($source->related_source($r));

            # sort means we keep a consistent order (with generated [pks])
            foreach my $field (sort map {$_->name} $sqlt_tbl->get_fields) {
                FOREIGN: foreach my $f (keys %$cond) {
                    if ($cond->{$f} eq "self.$field") {
                        (my $f_field = $f) =~ s/^foreign\.//;
                        push @{ $new_cols->{$r}->{ref_fields} }, $f_field;
                        push @{ $new_cols->{$r}->{fields} }, $field;
                        last FOREIGN;
                    }
                }
            };

            if ($rel_info->{attrs}->{accessor} eq 'multi') {
                $new_cols->{$r}->{rel_type} = 'has_many';
            }
            elsif (0 == scalar grep {not $sqlt_tbl->get_field($_)->is_foreign_key}
                                   @{$new_cols->{$r}->{fields}}) {
                $new_cols->{$r}->{rel_type} = 'belongs_to';
            }
            else {
                $new_cols->{$r}->{rel_type} = 'might_have';
            }
        }
    }

    # second pass to install m2m rels
    foreach my $tbl_name ($schema->sources) {
        my $source = $schema->source($tbl_name);
        my $from = make_path($source);
        my $sqlt_tbl = $sqlt->get_table($from);
        my $new_cols = $rels->{$from};

        foreach my $r (keys %$new_cols) {
            next unless $new_cols->{$r}->{rel_type} eq 'has_many';

            my $link = $new_cols->{$r}->{ref_table};
            next unless 2 == scalar keys %{$rels->{$link}}
                and 2 == scalar grep {$_->{rel_type} eq 'belongs_to'}
                                     values %{$rels->{$link}};

            foreach my $lrel (keys %{$rels->{$link}}) {
                next if $rels->{$link}->{$lrel}->{ref_table} eq $from;
                my $name = $rels->{$link}->{$lrel}->{ref_table};
                $name .= "_via_$link"
                    if exists $new_cols->{ $rels->{$link}->{$lrel}->{ref_table} };
                $new_cols->{ $name } = {
                    name => $name,
                    rel_type => 'many_to_many',
                    via => [$r, $lrel],
                };
                last;
            }
        }
    }

    foreach my $tbl_name (keys %$rels) {
        add_to_fields_at($sqlt->get_table($tbl_name), $_)
            for values %{$rels->{$tbl_name}};
    }

    return;
} # sub filter

1;
