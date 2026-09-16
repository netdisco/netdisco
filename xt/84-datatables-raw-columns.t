#!/usr/bin/env perl

# The "raw" DataTables renderer writes a column's value into the cell as
# HTML. That is right for a column whose value is markup the server built,
# and wrong for one whose value is data, so which renderer a column gets is
# a judgement per column.
#
# The sweep below reads each template's rendered data-nd-table attribute as
# JSON, which cannot see a render value built from a Perl variable rather
# than written as a literal. It therefore compares that against a literal
# source-text count and names any file where the two disagree, so a blind
# spot fails the test instead of passing it.

use strict;
use warnings;

use Test::More 0.88;
use JSON::PP qw/decode_json/;
use File::Find ();
use File::Spec;
use lib 'xt/lib';
use Test::Netdisco::Snapshot qw/render_template VIEW_ROOT/;

# (template path relative to share/views, column's "data" key) that must
# render as "escape".
my @ESCAPED_COLUMNS = (
    [ 'ajax/report/apchanneldist.tt',       'channel' ],
    [ 'ajax/report/apradiochannelpower.tt', 'channel' ],
    [ 'ajax/report/portvlanmismatch.tt',    'only_left_vlans' ],
    [ 'ajax/report/portvlanmismatch.tt',    'only_right_vlans' ],
    [ 'ajax/report/devicepoestatus.tt',     'module' ],
    [ 'ajax/search/port.tt',                'vlan_agg' ],
    [ 'ajax/search/port.tt',                'speed' ],
    [ 'ajax/search/port.tt',                'properties.remote_dns' ],
    [ 'ajax/search/port.tt',                'lastchange_stamp' ],
);

# (template path, column) pairs allowed to keep "render":"raw", each because
# the builder writing that markup was traced and escapes what it interpolates.
my @RAW_ALLOWLIST = ();

# One decoded spec per <table> in the file.
sub table_jsons {
    my $view = shift;
    my ($html, $error) = render_template($view);
    die "$view: $error" if defined $error;

    my @blobs = ($html =~ m/data-nd-table='(\{.*?\})'\s*>/gs);
    return map { decode_json($_) } @blobs;
}

# Counted from the source text, so it stands whether or not this test can
# render or parse the file. The JSON walk must reach the same number.
sub raw_literal_count {
    my $view = shift;
    open my $fh, '<:encoding(UTF-8)', File::Spec->catfile(VIEW_ROOT, $view)
        or die "$view: $!";
    local $/;
    my $source = <$fh>;
    my @hits = ($source =~ m/"render"\s*:\s*"raw"/g);
    return scalar @hits;
}

subtest 'namedColumns__each_of_the_nine_audited__declares_escape' => sub {
    my %by_view;
    foreach my $pair (@ESCAPED_COLUMNS) {
        push @{ $by_view{ $pair->[0] } }, $pair->[1];
    }

    foreach my $view ( sort keys %by_view ) {
        my ($spec) = table_jsons($view);
        my %render_for = map { $_->{data} => $_->{render} } @{ $spec->{columns} };

        foreach my $column ( @{ $by_view{$view} } ) {
            is( $render_for{$column}, 'escape',
                "$view column '$column' escapes its value" );
        }
    }
};

subtest 'sourceTemplates__every_render_raw_column__is_on_the_allowlist' => sub {
    my %allowed = map { sprintf( "%s\t%s", $_->[0], $_->[1] ) => 1 } @RAW_ALLOWLIST;

    my @views = ();
    File::Find::find({ no_chdir => 1, wanted => sub {
        return unless -f $File::Find::name and $File::Find::name =~ m/\.tt$/;
        push @views, File::Spec->abs2rel($File::Find::name, VIEW_ROOT);
    } }, VIEW_ROOT);

    my @unexpected  = ();
    my @blind_spots = ();

    foreach my $view ( sort @views ) {
        my $want = raw_literal_count($view);

        my @specs = eval { table_jsons($view) };
        my @cols  = map { @{ $_->{columns} || [] } } @specs;
        my $found = grep { ( $_->{render} // '' ) eq 'raw' } @cols;

        if ( $found != $want ) {
            push @blind_spots,
                "$view (source says $want, parse found $found)";
            next;
        }

        foreach my $col (@cols) {
            next unless ( $col->{render} // '' ) eq 'raw';
            my $key = "$view\t$col->{data}";
            push @unexpected, $key unless $allowed{$key};
        }
    }

    is( "@blind_spots", q{},
        'the parse sees every literal render:"raw" this test can find by text' );
    is( "@unexpected", q{},
        'no column declares render:"raw" outside the reviewed allowlist' );
};

done_testing;
