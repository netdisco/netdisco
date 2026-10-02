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

subtest 'portsTt__discovered_neighbor_with_detailed_inventory__escapes_remote_ip_id_and_type' => sub {
    my $stash = {
        params   => { c_neighbors => 1, n_detailed_inventory => 1 },
        settings => { domain_suffix => '' },
        results  => [ {
            remote_ip   => '<b>85a-ip</b>',
            remote_id   => '<b>85a-id</b>',
            remote_type => '<b>85a-type</b>',
            # the literal-only sibling print, pinned as untouched below
            manual_topo => 1,
            # a hashref stands in for the row: the template reaches the
            # branch holding these sites through get_column, not a key
            get_column => sub {
                my %col = ( neighbor_ip => '198.51.100.9',
                            neighbor_dns => 'switch.example.com' );
                return $col{ $_[0] };
            },
        } ],
    };
    my ($html, $error) = render_template('ajax/device/ports.tt', $stash);
    is $error, undef, 'template renders without error';

    contains_ok $html, '&lt;b&gt;85a-ip&lt;/b&gt;',   'remote_ip is escaped';
    lacks_ok    $html, '<b>85a-ip</b>',               'remote_ip raw markup is absent';
    contains_ok $html, '&lt;b&gt;85a-id&lt;/b&gt;',   'remote_id is escaped';
    lacks_ok    $html, '<b>85a-id</b>',               'remote_id raw markup is absent';
    contains_ok $html, '&lt;b&gt;85a-type&lt;/b&gt;', 'remote_type is escaped';
    lacks_ok    $html, '<b>85a-type</b>',             'remote_type raw markup is absent';
    contains_ok $html, 'class="fas fa-link text-warning"',
        'the sibling manual-topology class literal still renders as plain text';
};

subtest 'portsTt__undiscovered_neighbor_with_detailed_inventory__escapes_remote_id_and_type' => sub {
    my $stash = {
        params   => { c_neighbors => 1, n_detailed_inventory => 1 },
        settings => { domain_suffix => '' },
        results  => [ {
            remote_ip   => 'plain-85b-ip',
            remote_id   => '<b>85b-id</b>',
            remote_type => '<b>85b-type</b>',
            # falsy, so the row lands in the ELSIF branch holding the
            # other two sites
            get_column => sub { return undef },
        } ],
    };
    my ($html, $error) = render_template('ajax/device/ports.tt', $stash);
    is $error, undef, 'template renders without error';

    contains_ok $html, '&lt;b&gt;85b-id&lt;/b&gt;',   'remote_id is escaped';
    lacks_ok    $html, '<b>85b-id</b>',               'remote_id raw markup is absent';
    contains_ok $html, '&lt;b&gt;85b-type&lt;/b&gt;', 'remote_type is escaped';
    lacks_ok    $html, '<b>85b-type</b>',             'remote_type raw markup is absent';
};

subtest 'portsTt__no_remote_id_or_type__prints_nothing_for_the_detailed_inventory_line' => sub {
    my $stash = {
        params   => { c_neighbors => 1, n_detailed_inventory => 1 },
        settings => { domain_suffix => '' },
        results  => [ {
            remote_ip => 'plain-85c-ip',
            get_column => sub { return undef },
        } ],
    };
    my ($html, $error) = render_template('ajax/device/ports.tt', $stash);
    is $error, undef, 'template renders without error';
    lacks_ok $html, 'id: ',
        'the postfix IF still suppresses output when remote_id is unset';
};

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
