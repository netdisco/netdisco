#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::Snapshot qw/render_template all_templates snapshot_path/;

subtest 'allTemplates__in_repository__finds_every_tt_file' => sub {
    my @views = all_templates();
    cmp_ok scalar(@views), '>=', 100, 'finds the bulk of the templates';
    ok grep({ $_ eq 'index.tt' } @views), 'includes index.tt';
    ok grep({ $_ eq 'layouts/main.tt' } @views), 'includes layouts/main.tt';
    ok !grep({ m{^share/views/} } @views), 'paths are relative to share/views';
};

subtest 'renderTemplate__simple_sidebar__returns_markup_not_error' => sub {
    my ($html, $error) = render_template('sidebar/report/portmultinodes.tt');
    is $error, undef, 'no error';
    ok defined $html && length $html, 'produced output';
    like $html, qr/class="/, 'output carries class attributes';
};

subtest 'renderTemplate__unknown_template__returns_error_not_html' => sub {
    my ($html, $error) = render_template('does/not/exist.tt');
    is $html, undef, 'no html';
    ok defined $error && length $error, 'an error string is returned';
};

subtest 'snapshotPath__nested_template__mirrors_the_view_tree' => sub {
    is snapshot_path('ajax/device/ports.tt'),
       'xt/snapshots/ajax/device/ports.tt.html',
       'snapshot path mirrors the template path';
};

subtest 'renderedOutput__every_template__matches_its_committed_snapshot' => sub {
    # The snapshots are bulky and are kept out of the distribution, so they are
    # present in a git checkout and absent from an unpacked tarball. An absent
    # tree means there is nothing to compare against; individual files missing
    # below means a template was added without regenerating, which is a real
    # failure and must stay one.
    plan skip_all => 'xt/snapshots is not shipped in the distribution'
      unless -d 'xt/snapshots';

    my @views = all_templates();
    my @missing = ();
    my @differs = ();
    my @errored = ();

    foreach my $view (@views) {
        my ($html, $error) = render_template($view);
        if (defined $error) { push @errored, "$view: $error"; next }

        my $path = snapshot_path($view);
        if (!-f $path) { push @missing, $view; next }

        open my $fh, '<:encoding(UTF-8)', $path or die "$path: $!";
        my $want = do { local $/; <$fh> };
        close $fh;

        push @differs, $view if $want ne $html;
    }

    is scalar(@errored), 0, 'every template renders without error'
      or diag "failed to render:\n  " . join("\n  ", @errored);

    is scalar(@missing), 0, 'every template has a committed snapshot'
      or diag "no snapshot for:\n  " . join("\n  ", @missing)
            . "\nrun: xt/bin/regenerate-snapshots";

    is scalar(@differs), 0, 'no rendered output differs from its snapshot'
      or diag "changed:\n  " . join("\n  ", @differs)
            . "\nreview the diff, then run: xt/bin/regenerate-snapshots";
};

done_testing;
