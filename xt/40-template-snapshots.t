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

done_testing;
