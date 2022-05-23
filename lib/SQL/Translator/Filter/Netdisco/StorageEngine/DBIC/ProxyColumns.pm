package SQL::Translator::Filter::Netdisco::StorageEngine::DBIC::ProxyColumns;

# The DBIC Relation proxy atribute can be used to import accessors from
# related tables. This filter parses the attribute and installs columns
# which we can display.

use strict;
use warnings;

use SQL::Translator::Netdisco::Utils;

sub filter {
    my ($sqlt, @args) = @_;
    my $schema = shift @args;

    foreach my $tbl_name ($schema->sources) {
        my $source = $schema->source($tbl_name);
        my $from = make_path($source);
        my $sqlt_tbl = $sqlt->get_table($from)
            or die "mismatched (proxy) table name between SQLT and DBIC: [$tbl_name]\n";

        foreach my $r ($source->relationships) {
            my $rel_info = $source->relationship_info($r);
            next if $rel_info->{attrs}->{accessor} eq 'multi';

            # catch dangling rels and skip them
            next unless eval{$source->related_source($r)};

            next unless exists $rel_info->{attrs}->{proxy}
                and $rel_info->{attrs}->{proxy};

            # proxy columns are added
            my $proxies = $rel_info->{attrs}->{proxy};

            # get a list of proxy names - annoying that we have to parse :(
            my %proxy = ref $proxies eq ref {} ? %$proxies
                        : ref $proxies eq ref [] ? (map {ref $_ ? %$_ : ($_ => $_)} @$proxies)
                        : ( $proxies => $proxies );

            my $f_tbl = make_path($source->related_source($r));
            (my $col = (values %{$rel_info->{cond}})[0]) =~ s/^self\.//;
            # (my $f_col = (keys %{$rel_info->{cond}})[0]) =~ s/^foreign\.//;

            while (my ($local, $remote) = each %proxy) {
                next if $sqlt_tbl->get_field($local);

                my $auto  = $sqlt->get_table($f_tbl)->get_field($remote)->is_auto_increment;
                my $type  = $sqlt->get_table($f_tbl)->get_field($remote)->data_type;
                my $size  = $sqlt->get_table($f_tbl)->get_field($remote)->size;

                $sqlt_tbl->add_field(
                    name => $local,
                    display_name => make_label($local),
                    data_type => $type,
                    size => $size,
                    is_auto_increment => $auto,
                    extra => {
                        is_proxy => 1,
                        proxy_field => $col,
                        proxy_rel_field => $remote,
                    },
                );
            }
        }
    }
}

1;
