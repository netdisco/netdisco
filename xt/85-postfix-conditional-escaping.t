#!/usr/bin/env perl

use strict;
use warnings;

# Template::AutoFilter skips postfix IF, UNLESS, ELSIF and ELSE. A print of
# the form [% expr IF cond %] parses as one directive carrying both the
# expression and the condition, so AUTO_FILTER never reaches it whatever it
# is configured to, and each site filters its expression explicitly instead.
#
# Proven by rendering rather than by reading the template source, because a
# source-text assertion shows an edit was made and never that the escaped
# output reaches the page. Each subtest also pins a neighboring literal-only
# postfix print as untouched: those carry markup, and escaping one would put
# visible entities on the page where an icon belongs.

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::Snapshot 'render_template';

sub next_iterator {
    my @rows = @_;
    return sub { shift @rows };
}

# index() rather than a regexp: an escaped closing tag, '&lt;/b&gt;', carries
# a literal slash that collides with the qr// delimiter, and \Q..\E does not
# change the delimiter scan.
sub contains_ok {
    my ($html, $needle, $name) = @_;
    ok( index( $html, $needle ) >= 0, $name );
}

sub lacks_ok {
    my ($html, $needle, $name) = @_;
    ok( index( $html, $needle ) < 0, $name );
}

# ajax/device/ports.tt used to be checked here, for the neighbor's remote_ip,
# remote_id and remote_type. It no longer draws the rows: netdisco-ports.js
# does, from JSON, and escapes through DataTable.util.escapeHtml, where no
# postfix IF can skip a filter. The same three cases, and the literal-only
# class print beside them, are in xt/js/ports-table.test.js.

subtest 'nodeByIpTt__row_dns__escapes_dns_and_leaves_the_archived_icon_as_markup' => sub {
    my $stash = {
        settings => { domain_suffix => '' },
        macs => { next => next_iterator(
            { ip => '192.0.2.1', active => 0, nbname => undef,
              dns => '<b>85d-dns</b>' },
        ) },
    };
    my ($html, $error) = render_template('ajax/search/node_by_ip.tt', $stash);
    is $error, undef, 'template renders without error';

    contains_ok $html, '&lt;b&gt;85d-dns&lt;/b&gt;', 'row.dns is escaped';
    lacks_ok    $html, '<b>85d-dns</b>',             'row.dns raw markup is absent';
    contains_ok $html, '<i class="fas fa-book nd_icon-archived"></i>',
        'the sibling archived-node icon literal still renders as a tag';
    lacks_ok    $html, '&lt;i class=',
        'the sibling archived-node icon literal is not itself escaped';
};

subtest 'nodeByIpTt__ni_dns__escapes_dns' => sub {
    my $stash = {
        settings => { domain_suffix => '' },
        macs => { next => next_iterator(
            { ip => '192.0.2.1', active => 1, nbname => undef, nodeips => [
                { ip => '192.0.2.2', active => 1, dns => '<b>85e-dns</b>' },
            ] },
        ) },
    };
    my ($html, $error) = render_template('ajax/search/node_by_ip.tt', $stash);
    is $error, undef, 'template renders without error';

    contains_ok $html, '&lt;b&gt;85e-dns&lt;/b&gt;', 'ni.dns is escaped';
    lacks_ok    $html, '<b>85e-dns</b>',             'ni.dns raw markup is absent';
};

subtest 'nodeByIpTt__nodeip_dns__escapes_dns' => sub {
    my $stash = {
        settings => { domain_suffix => '' },
        macs => { next => next_iterator(
            { ip => '192.0.2.1', active => 1, nbname => undef,
              ip_aliases => sub { [
                  { ip => '192.0.2.3', active => 1, dns => '<b>85f-dns</b>' },
              ] } },
        ) },
    };
    my ($html, $error) = render_template('ajax/search/node_by_ip.tt', $stash);
    is $error, undef, 'template renders without error';

    contains_ok $html, '&lt;b&gt;85f-dns&lt;/b&gt;', 'nodeip.dns is escaped';
    lacks_ok    $html, '<b>85f-dns</b>',             'nodeip.dns raw markup is absent';
};

subtest 'nodeByMacTt__row_dns__escapes_dns_and_leaves_the_archived_icon_as_markup' => sub {
    my $stash = {
        settings => { domain_suffix => '' },
        ips => { next => next_iterator(
            { ip => '192.0.2.1', active => 0, dns => '<b>85g-dns</b>' },
        ) },
    };
    my ($html, $error) = render_template('ajax/search/node_by_mac.tt', $stash);
    is $error, undef, 'template renders without error';

    contains_ok $html, '&lt;b&gt;85g-dns&lt;/b&gt;', 'row.dns is escaped';
    lacks_ok    $html, '<b>85g-dns</b>',             'row.dns raw markup is absent';
    contains_ok $html, '<i class="fas fa-book nd_icon-archived"></i>',
        'the sibling archived-node icon literal still renders as a tag';
    lacks_ok    $html, '&lt;i class=',
        'the sibling archived-node icon literal is not itself escaped';
};

subtest 'portNodesTt__time_last_age__escapes_age_and_leaves_the_archived_icon_as_markup' => sub {
    my $stash = {
        params => { n_age => 1 },
        row => { remote_ip => '', is_uplink => 0, stitched_nodes => [
            { active => 0, time_last_age => '<b>85h-age</b>' },
        ] },
    };
    my ($html, $error) = render_template('ajax/device/port_nodes.tt', $stash);
    is $error, undef, 'template renders without error';

    contains_ok $html, '&lt;b&gt;85h-age&lt;/b&gt;', 'time_last_age is escaped';
    lacks_ok    $html, '<b>85h-age</b>',             'time_last_age raw markup is absent';
    contains_ok $html,
        '<i class="fas fa-book nd_icon-archived" title="Archived node (inactive)"></i>',
        'the sibling archived-node icon literal still renders as a tag';
    lacks_ok    $html, '&lt;i class=',
        'the sibling archived-node icon literal is not itself escaped';
};

subtest 'portNodesTt__age_param_off__prints_nothing_for_the_age_line' => sub {
    my $stash = {
        params => { n_age => 0 },
        row => { remote_ip => '', is_uplink => 0, stitched_nodes => [
            { active => 1, time_last_age => '2 hours' },
        ] },
    };
    my ($html, $error) = render_template('ajax/device/port_nodes.tt', $stash);
    is $error, undef, 'template renders without error';
    lacks_ok $html, '2 hours',
        'the postfix IF still suppresses output when params.n_age is false';
};

done_testing;
