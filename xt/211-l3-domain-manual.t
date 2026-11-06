#!/usr/bin/env perl

use strict;
use warnings;

# vrf_domains lets an operator place a VRF (or a VRF's whole evidence domain)
# in a named domain. A malformed entry or a regex group must warn and be
# skipped without stopping inference, and the recompute owns the manual member
# rows, so an entry that goes away must return its VRFs to inference. Only the
# database handle, the settings, the warning sink and the ACL matcher are
# faked, as in xt/187.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Util::L3Domain qw/manual_l3_entries manual_l3_members recompute_l3_domains/;

my (%settings, @warnings, @sql, @acl_calls, $acl_answer, $hostname_lookups);
my (@resolve_rows, @candidate_rows, @join_rows, @device_rows, @writes);

{
  no warnings 'redefine';
  *App::Netdisco::Util::L3Domain::setting = sub { return $settings{$_[0]} };
  *App::Netdisco::Util::L3Domain::warning = sub { push @warnings, join '', @_ };
  *App::Netdisco::Util::L3Domain::acl_matches_only = sub {
    push @acl_calls, [@_];
    return $acl_answer->(@_);
  };
  *App::Netdisco::Util::Permission::hostname_from_ip = sub { ++$hostname_lookups; die "DNS lookup attempted\n" };
}

package FakeDbh;
sub new { return bless {}, $_[0] }
sub selectall_arrayref {
  my ($self, $statement, undef, @binds) = @_;
  push @sql, [$statement, @binds];
  my @dispatch = (
    [ qr/unnest\(\?::text/            => \@resolve_rows ],
    [ qr/SELECT \* FROM device/  => \@device_rows ],
    [ qr/e\.key = ANY/          => \@join_rows ],
    [ qr/e\.vrf = ANY/          => \@candidate_rows ],
  );
  for my $route (@dispatch) {
    return [ @{ $route->[1] } ] if $statement =~ $route->[0];
  }
  die "unexpected query: $statement";
}
sub do { my ($self, $statement, undef, @binds) = @_; push @writes, [$statement, @binds]; return '0E0' }
sub selectrow_array { my ($self, $statement, undef, @binds) = @_; push @writes, [$statement, @binds]; return 0 }

package FakeSchema;
sub new     { return bless { dbh => FakeDbh->new }, $_[0] }
sub txn_do  { return $_[1]->() }
sub storage { return $_[0] }
sub dbh_do  { my ($self, $code) = @_; return $code->($self, $self->{dbh}) }

package main;

# the one recompute statement, as sent, and its text with whitespace folded
sub recompute_statement {
  my ($statement) = grep { $_->[0] =~ /^WITH man AS/ } @writes;
  (my $flat = $statement->[0]) =~ s/\s+/ /g;
  return ($statement, $flat);
}

sub reset_world {
  %settings = (host_groups => {});
  @warnings = @sql = @acl_calls = @resolve_rows = @candidate_rows = @join_rows = @device_rows = @writes = ();
  $hostname_lookups = 0;
  $acl_answer = sub { 1 };
}

sub entries_for {
  my $list = shift;
  $settings{vrf_domains} = $list;
  return manual_l3_entries(FakeSchema->new);
}

sub members_for {
  my $entries = shift;
  return manual_l3_members(FakeSchema->new, $entries);
}

sub entry {
  my %e = (domain => 'A', device => '10.0.0.1', vrf => 'blue', join => 0, @_);
  return \%e;
}

sub placed {
  my $members = shift;
  return { map { ("$_->{ip}/$_->{vrf}" => $_->{domain}) } @$members };
}

subtest 'manual_entries__device_alias__resolved_to_canonical_ip' => sub {
  reset_world();
  @resolve_rows = ({ input => '192.0.2.99', ip => '10.0.0.1' });
  my $entries = entries_for([ { domain => 'CUSTOMER-A', device => '192.0.2.99', vrf => 'blue', join => 'true' } ]);
  is_deeply($entries, [ { domain => 'CUSTOMER-A', device => '10.0.0.1', vrf => 'blue', join => 1 } ]);
  is_deeply([@warnings], [], 'no warning');
};

subtest 'manual_entries__unknown_device__warned_and_skipped' => sub {
  reset_world();
  my $entries = entries_for([ entry(domain => 'CUSTOMER-A', device => '192.0.2.99', vrf => 'RED') ]);
  is_deeply($entries, []);
  is(scalar @warnings, 1, 'one warning');
  like($warnings[0], qr/CUSTOMER-A.*192\.0\.2\.99.*RED/s, 'names domain, device and vrf');
  like($warnings[0], qr/discover|known device/i, 'says what to change');
};

subtest 'manual_entries__group_device__kept_as_group' => sub {
  reset_world();
  $settings{host_groups} = { 'branch-ces' => ['10.0.0.0/8'] };
  my $entries = entries_for([ entry(device => 'group:branch-ces') ]);
  is_deeply($entries, [ entry(device => 'group:branch-ces') ]);
  is(scalar(grep { $_->[0] =~ /unnest\(\?::text/ } @sql), 0, 'no address lookup for a group');
  is_deeply([@warnings], []);
};

subtest 'manual_members__group_entry__matches_live_members_only' => sub {
  reset_world();
  $settings{host_groups} = { 'branch-ces' => ['10.0.0.1'] };
  @candidate_rows = (
    { ip => '10.0.0.1', vrf => 'RED', key => 'name:RED' },
    { ip => '10.0.0.2', vrf => 'RED', key => 'name:RED' },
    { ip => '10.0.0.3', vrf => 'RED', key => 'name:RED' },
  );
  @device_rows = ({ ip => '10.0.0.1' }, { ip => '10.0.0.2' });
  $acl_answer = sub { $_[0]->{ip} eq '10.0.0.1' };
  my $members = members_for([ entry(device => 'group:branch-ces', vrf => 'RED') ]);
  is_deeply(placed($members), { '10.0.0.1/RED' => 'A' }, 'matching device with the VRF only; a device row-less candidate is not a member');
};

subtest 'manual_members__unknown_group__warned_matches_nothing' => sub {
  reset_world();
  @candidate_rows = ({ ip => '10.0.0.1', vrf => 'RED', key => 'name:RED' });
  @device_rows = ({ ip => '10.0.0.1' });
  my $members = members_for([ entry(domain => 'CUSTOMER-A', device => 'group:nope', vrf => 'RED') ]);
  is_deeply($members, []);
  is(scalar @warnings, 1, 'one warning');
  like($warnings[0], qr/CUSTOMER-A.*group:nope.*RED/s, 'names the entry');
  like($warnings[0], qr/host_groups/, 'says where to define it');
  is(scalar @acl_calls, 0, 'matcher not consulted');
};

subtest 'manual_entries__group_with_regex_rule__warned_and_skipped' => sub {
  reset_world();
  $settings{host_groups} = {
    direct  => [ '10.0.0.0/8', qr/^pe/ ],
    nested  => [ 'group:direct' ],
    negated => [ '!group:direct' ],
    fine    => [ '10.0.0.0/8', 'tag:edge' ],
  };
  my $entries = entries_for([
    entry(domain => 'D1', device => 'group:direct'),
    entry(domain => 'D2', device => 'group:nested'),
    entry(domain => 'D3', device => 'group:negated'),
    entry(domain => 'D5', device => 'group:fine'),
  ]);
  is_deeply([ map { $_->{domain} } @$entries ], [qw/D5/], 'plain groups survive');
  is(scalar @warnings, 3, 'one warning per refused entry');
  like($warnings[$_], qr/regular expression/i, "warning $_ says why") for 0 .. 2;
  like($warnings[1], qr/group:nested.*group:direct|group:direct.*group:nested/s, 'names the referenced group');
  is($hostname_lookups, 0, 'no reverse DNS lookup');
};

subtest 'manual_entries__group_with_hostname_rule__warned_and_refused' => sub {
  reset_world();
  my $forward_lookups = 0;
  no warnings 'redefine';
  local *NetAddr::IP::Lite::new = do { my $orig = \&NetAddr::IP::Lite::new; sub { ++$forward_lookups if defined $_[1] and $_[1] =~ m/[g-z]{2}/i; goto &$orig } };
  $settings{host_groups} = {
    names   => [ '10.0.0.0/8', 'ce1.example.net' ],
    nested  => [ 'group:names' ],
    plain   => [ 'localhost' ],
    cron    => [ '* * * * *' ],
    allowed => [ '10.0.0.1', '10.0.0.0/8', '10.1.2.3-9', '2001:db8::/32', '2001:db8::1-9', 'fe80::1',
                 'prop:vendor:cisco', 'tag:edge', 'cf:site:north', '!tag:old', 'group:allowed2', 'op:and' ],
    allowed2 => [ '192.0.2.0/24', '10.5', '!10.0.0.9' ],
  };
  my $entries = entries_for([ map { entry(domain => $_, device => "group:$_") } qw/names nested plain cron allowed/ ]);
  is_deeply([ map { $_->{domain} } @$entries ], ['allowed'], 'only address, prefix, range, prop:, tag:, cf: and group: rules survive');
  is(scalar @warnings, 4, 'one warning per refused entry');
  like($warnings[0], qr/names.*ce1\.example\.net/s, 'names the group and the first offending rule');
  like($warnings[1], qr/nested.*names.*ce1\.example\.net/s, 'a nested group is traced to the holder and the rule');
  like($warnings[2], qr/localhost/, 'a bare hostname is refused');
  like($warnings[3], qr/\* \* \* \* \*/, 'a cron rule is refused');
  like($warnings[$_], qr/DNS|time of day/i, "warning $_ says why") for 0 .. 3;
  is($hostname_lookups, 0, 'no reverse DNS lookup');
  is($forward_lookups, 0, 'no hostname handed to the address parser');
};

subtest 'manual_entries__group_cycle__warned_and_refused' => sub {
  reset_world();
  $settings{host_groups} = {
    loop_a => [ 'group:loop_b', '10.1.0.0/16' ],
    loop_b => [ '!group:loop_a' ],
    self   => [ 'group:self' ],
    entry  => [ 'group:loop_a' ],
    fine   => [ '10.0.0.0/8' ],
  };
  my $entries = entries_for([ map { entry(domain => $_, device => "group:$_") } qw/loop_a self entry fine/ ]);
  is_deeply([ map { $_->{domain} } @$entries ], ['fine'], 'only the acyclic group survives');
  is(scalar @warnings, 3, 'one warning per refused entry');
  like($warnings[0], qr/loop_a.*loop_b.*loop_a/s, 'names the cycle') or diag $warnings[0];
  like($warnings[$_], qr/cycl|circular|loop/i, "warning $_ says why") for 0 .. 2;
};

subtest 'manual_members__group_entry__matcher_gets_device_row' => sub {
  reset_world();
  @candidate_rows = ({ ip => '10.0.0.1', vrf => 'RED', key => 'name:RED' });
  @device_rows = ({ ip => '10.0.0.1', tags => ['edge'], model => 'x' });
  $settings{host_groups} = { g => ['tag:edge'] };
  members_for([ entry(device => 'group:g', vrf => 'RED') ]);
  is(scalar @acl_calls, 1);
  is(ref $acl_calls[0][0], 'HASH', 'a row, not a bare address');
  is_deeply($acl_calls[0][0]{tags}, ['edge'], 'with its columns');
  is($acl_calls[0][1], 'group:g', 'against the named group');
  is(scalar(grep { $_->[0] =~ /SELECT \* FROM device/ } @sql), 1, 'device rows fetched in one query');
};

subtest 'manual_entries__ip_entries__resolved_in_one_query' => sub {
  reset_world();
  @resolve_rows = (
    { input => '192.0.2.1', ip => '10.0.0.1' },
    { input => '192.0.2.2', ip => '10.0.0.2' },
    { input => '10.0.0.3',  ip => '10.0.0.3' },
  );
  my $entries = entries_for([
    entry(device => '192.0.2.1'), entry(device => '192.0.2.2', vrf => 'red'),
    entry(device => '10.0.0.3', vrf => 'green'), entry(device => '192.0.2.1', vrf => 'red'),
  ]);
  is(scalar @$entries, 4);
  my @lookups = grep { $_->[0] =~ /unnest\(\?::text/ } @sql;
  is(scalar @lookups, 1, 'one query');
  is_deeply([ sort @{ $lookups[0][1] } ], [qw/10.0.0.3 192.0.2.1 192.0.2.2/], 'each distinct address once');
  like($lookups[0][0], qr/device_ip_resolved/, 'the view get_device resolves through');
  like($lookups[0][0], qr/ip = \w+\.alias/, 'a device own address wins');
};

subtest 'manual_members__empty_setting__no_queries' => sub {
  for my $empty ([], undef) {
    reset_world();
    my $entries = entries_for($empty);
    is_deeply($entries, []);
    is_deeply(members_for($entries), []);
    is(scalar @sql, 0, 'no SQL');
    is(scalar @warnings, 0, 'no warning');
  }
};

subtest 'manual_members__ip_beats_group_beats_join__by_level' => sub {
  my @entries = (
    entry(domain => 'ZIP',   device => '10.0.0.2', vrf => 'RED'),
    entry(domain => 'MGRP',  device => 'group:g',  vrf => 'RED'),
    entry(domain => 'AJOIN', device => '10.0.0.1', vrf => 'BLUE', join => 1),
  );
  my $run = sub {
    my @use = @_;
    reset_world();
    $settings{host_groups} = { g => ['10.0.0.2'] };
    @device_rows = ({ ip => '10.0.0.2' });
    @candidate_rows = ({ ip => '10.0.0.1', vrf => 'BLUE', key => 'rt:x/x' }, { ip => '10.0.0.2', vrf => 'RED', key => 'rt:x/x' });
    @join_rows = @candidate_rows;
    return placed(members_for([ @entries[@use] ]));
  };
  is($run->(0, 1, 2)->{'10.0.0.2/RED'}, 'ZIP', 'IP entry wins');
  is($run->(1, 2)->{'10.0.0.2/RED'}, 'MGRP', 'group beats join');
  is($run->(2)->{'10.0.0.2/RED'}, 'AJOIN', 'join alone');
};

subtest 'manual_entries__malformed__warned_and_skipped' => sub {
  my @bad = (
    [ 'setting a string'     => 'oops' ],
    [ 'setting a hash'       => { domain => 'A' } ],
    [ 'entry a string'       => ['oops'] ],
    [ 'no domain'            => [ { device => '10.0.0.1', vrf => 'v' } ] ],
    [ 'no device'            => [ { domain => 'A', vrf => 'v' } ] ],
    [ 'no vrf'               => [ { domain => 'A', device => '10.0.0.1' } ] ],
    [ 'range'                => [ entry(device => '10.0.0.0/24') ] ],
    [ 'dash range'           => [ entry(device => '10.0.0.1-10.0.0.9') ] ],
    [ 'op:and'               => [ entry(device => 'op:and') ] ],
    [ 'negated group'        => [ entry(device => '!group:g') ] ],
    [ 'two groups'           => [ entry(device => ['group:g', 'group:h']) ] ],
    [ 'two groups one string'=> [ entry(device => 'group:g group:h') ] ],
    [ 'hostname'             => [ entry(device => 'switch1.example.com') ] ],
    [ 'empty domain'         => [ entry(domain => '') ] ],
    [ 'default domain'       => [ entry(domain => 'default') ] ],
    [ 'empty vrf'            => [ entry(vrf => '') ] ],
    [ 'default vrf'          => [ entry(vrf => 'default') ] ],
    [ 'join not boolean'     => [ entry(join => 'maybe') ] ],
  );
  for my $case (@bad) {
    reset_world();
    $settings{host_groups} = { g => ['10.0.0.1'], h => ['10.0.0.2'] };
    my $entries = entries_for($case->[1]);
    is_deeply($entries, [], "$case->[0]: skipped");
    is(scalar @warnings, 1, "$case->[0]: one warning");
  }
  reset_world();
  @resolve_rows = ({ input => '10.0.0.1', ip => '10.0.0.1' });
  my $entries = entries_for([ entry(domain => ''), entry(domain => 'GOOD') ]);
  is_deeply([ map { $_->{domain} } @$entries ], ['GOOD'], 'a good entry beside a bad one survives');
  like($warnings[0], qr/domain/, 'warning names the problem');

  reset_world();
  $settings{vrf_domains} = [ entry(domain => '') ];
  recompute_l3_domains(FakeSchema->new);
  is(scalar @writes, 2, 'inference still runs (the lock and the recompute statement)');
};

subtest 'manual_entries__join_ref_or_object__warned_and_skipped_no_die' => sub {
  for my $case ([ array => [1] ], [ hash => {} ], [ code => sub { 1 } ], [ object => bless({}, 'Some::Thing') ]) {
    reset_world();
    my $entries = eval { entries_for([ entry(join => $case->[1]) ]) };
    is($@, '', "$case->[0]: does not die");
    is_deeply($entries, [], "$case->[0]: skipped");
    is(scalar @warnings, 1, "$case->[0]: one warning");
    unlike($warnings[0] // '', qr/0x[0-9a-f]+/, "$case->[0]: no memory address in the warning");
  }
  reset_world();
  @resolve_rows = ({ input => '10.0.0.1', ip => '10.0.0.1' });
  require JSON::PP;
  my $entries = eval { entries_for([ entry(join => JSON::PP::true()), entry(domain => 'F', join => JSON::PP::false()) ]) };
  is($@, '', 'JSON::PP::Boolean does not die');
  is_deeply([ map { $_->{join} } @$entries ], [1, 0], 'read as booleans');
};

subtest 'manual_entries__short_ipv4_form__warned_and_skipped' => sub {
  for my $bad (qw/10 10.1 10.0.0 010.0.0.1 256.0.0.1 10.0.0.1.1 1:2/) {
    reset_world();
    my $entries = entries_for([ entry(device => $bad) ]);
    is_deeply($entries, [], "$bad: skipped");
    is(scalar @warnings, 1, "$bad: one warning");
    is(scalar(grep { $_->[0] =~ /unnest\(\?::text/ } @sql), 0, "$bad: never sent to the database");
  }
  reset_world();
  @resolve_rows = ({ input => '2001:db8::1', ip => '2001:db8::1' });
  my $entries = entries_for([ entry(device => '2001:db8::1') ]);
  is(scalar @$entries, 1, 'an IPv6 literal passes');
};

subtest 'manual_entries__ipv6_dotted_tail_leading_zero__warned_and_skipped' => sub {
  for my $bad (qw/::01.2.3.4 ::1.02.3.4 ::1.2.3 ::1.2.3.256 ::1.2.3.4.5/) {
    reset_world();
    is_deeply(entries_for([ entry(device => $bad) ]), [], "$bad: skipped");
    is(scalar @warnings, 1, "$bad: one warning");
    is(scalar(grep { $_->[0] =~ /unnest\(\?::text/ } @sql), 0, "$bad: never sent to the database");
  }
  for my $good (qw/::1.2.3.4 1:2:3:4:5:6:1.2.3.4/) {
    reset_world();
    @resolve_rows = ({ input => $good, ip => $good });
    is(scalar @{ entries_for([ entry(device => $good) ]) }, 1, "$good: accepted");
  }
};

subtest 'manual_members__plain_entry__only_that_vrf_moves' => sub {
  reset_world();
  @candidate_rows = ({ ip => '10.0.0.1', vrf => 'RED', key => 'rt:x/x' });
  @join_rows = ({ ip => '10.0.0.1', vrf => 'RED', key => 'rt:x/x' }, { ip => '10.0.0.9', vrf => 'BLUE', key => 'rt:x/x' });
  my $members = members_for([ entry(device => '10.0.0.1', vrf => 'RED') ]);
  is_deeply(placed($members), { '10.0.0.1/RED' => 'A' });
  is(scalar(grep { $_->[0] =~ /e\.key = ANY/ } @sql), 0, 'no evidence-domain read');
};

subtest 'manual_members__join_entry__whole_evidence_domain_brought' => sub {
  reset_world();
  @candidate_rows = ({ ip => '10.0.0.1', vrf => 'RED', key => 'rt:x/x' });
  @join_rows = (
    { ip => '10.0.0.1', vrf => 'RED',   key => 'rt:x/x' },
    { ip => '10.0.0.5', vrf => 'BLUE',  key => 'rt:x/x' },
    { ip => '10.0.0.6', vrf => 'GREEN', key => 'rt:x/x' },
  );
  my $members = members_for([ entry(device => '10.0.0.1', vrf => 'RED', join => 1) ]);
  is_deeply(placed($members), { '10.0.0.1/RED' => 'A', '10.0.0.5/BLUE' => 'A', '10.0.0.6/GREEN' => 'A' });
  my %direct = map { ("$_->{ip}/$_->{vrf}" => $_->{direct}) } @$members;
  is_deeply(\%direct, { '10.0.0.1/RED' => 1, '10.0.0.5/BLUE' => 0, '10.0.0.6/GREEN' => 0 }, 'only the named VRF is direct');
  is_deeply([ sort map { $_->{level} } @$members ], [qw/ip join join/]);
  my ($join_query) = grep { $_->[0] =~ /e\.key = ANY/ } @sql;
  is_deeply($join_query->[1], ['rt:x/x'], 'keyed by the entry evidence key');
};

subtest 'manual_members__named_vrf_beats_join__split_out' => sub {
  reset_world();
  @candidate_rows = (
    { ip => '10.0.0.1', vrf => 'RED',  key => 'rt:x/x' },
    { ip => '10.0.0.2', vrf => 'BLUE', key => 'rt:x/x' },
  );
  @join_rows = @candidate_rows;
  my $members = members_for([
    entry(domain => 'A', device => '10.0.0.1', vrf => 'RED', join => 1),
    entry(domain => 'B', device => '10.0.0.2', vrf => 'BLUE'),
  ]);
  is_deeply(placed($members), { '10.0.0.1/RED' => 'A', '10.0.0.2/BLUE' => 'B' });
  is(scalar @warnings, 0, 'a more specific entry is not a conflict');
};

subtest 'manual_members__vrf_in_two_entries_same_level__first_domain_name_wins_and_warns' => sub {
  reset_world();
  @candidate_rows = ({ ip => '10.0.0.1', vrf => 'RED', key => 'name:RED' });
  my $members = members_for([
    entry(domain => 'beta',  device => '10.0.0.1', vrf => 'RED'),
    entry(domain => 'alpha', device => '10.0.0.1', vrf => 'RED'),
  ]);
  is_deeply(placed($members), { '10.0.0.1/RED' => 'alpha' });
  is(scalar @warnings, 1, 'one warning');
  like($warnings[0], qr/alpha.*beta|beta.*alpha/s, 'names both domains');
};

subtest 'recompute__manual_vrf_gone_from_device_vrf__row_removed' => sub {
  reset_world();
  @resolve_rows = ({ input => '10.0.0.1', ip => '10.0.0.1' });
  $settings{vrf_domains} = [ entry(device => '10.0.0.1', vrf => 'gone') ];
  recompute_l3_domains(FakeSchema->new);
  my ($statement, $flat) = recompute_statement();
  unlike($flat, qr/source = 'inferred'/, 'manual rows are covered');
  is_deeply([ @{$statement}[1 .. 4] ], [ [], [], [], [] ], 'device_vrf has no such VRF, so the desired manual set is empty');
  like($flat, qr/unnest\(\?::inet\[\], \?::text\[\], \?::text\[\], \?::text\[\]\)/, 'manual set passed as arrays');
  like($flat, qr/gone AS \( DELETE FROM l3_domain_member m WHERE NOT EXISTS \(SELECT 1 FROM desired d\b/, 'the delete reads that set');
};

subtest 'recompute__manual_vrf_present__desired_set_wins_over_evidence' => sub {
  reset_world();
  @resolve_rows = ({ input => '10.0.0.1', ip => '10.0.0.1' });
  @candidate_rows = ({ ip => '10.0.0.1', vrf => 'blue', key => 'name:blue' });
  $settings{vrf_domains} = [ entry(domain => 'CUSTOMER-A', device => '10.0.0.1', vrf => 'blue') ];
  recompute_l3_domains(FakeSchema->new);
  my ($statement, $flat) = recompute_statement();
  is_deeply([ @{$statement}[1 .. 4] ],
    [ ['10.0.0.1'], ['blue'], ['manual:CUSTOMER-A'], ['vrf_domains CUSTOMER-A'] ], 'desired arrays bound once');
  like($flat, qr/SELECT d\.ip, d\.vrf, m\.id AS domain_id, d\.reason, d\.source FROM desired d/, 'source comes from the desired row');
  like($flat, qr/substr\(man\.key, 8\) AS display/, 'manual domain is named after the setting');
  like($flat, qr/NOT EXISTS \(SELECT 1 FROM man WHERE man\.ip = e\.ip AND man\.vrf = e\.vrf\)/, 'a manual pair is not also inferred');
};

subtest 'recompute__config_entry_removed__vrf_back_to_inference' => sub {
  reset_world();
  recompute_l3_domains(FakeSchema->new);
  my (undef, $flat) = recompute_statement();
  unlike($flat, qr/source = 'inferred'/, 'a manual row with no entry is deleted too');
  like($flat, qr/t\.domain_id <> m\.domain_id/, 'moved when the desired domain is not its domain');
  is(scalar(grep { $_->[0] =~ /FROM device_vrf/ } @sql), 0, 'no manual reads');
};

subtest 'recompute__join_brought_rows__reason_names_the_domain' => sub {
  reset_world();
  @resolve_rows = ({ input => '10.0.0.1', ip => '10.0.0.1' });
  @candidate_rows = ({ ip => '10.0.0.1', vrf => 'RED', key => 'rt:x/x' });
  @join_rows = ({ ip => '10.0.0.1', vrf => 'RED', key => 'rt:x/x' }, { ip => '10.0.0.5', vrf => 'BLUE', key => 'rt:x/x' });
  $settings{vrf_domains} = [ entry(device => '10.0.0.1', vrf => 'RED', join => 1) ];
  recompute_l3_domains(FakeSchema->new);
  my ($statement) = recompute_statement();
  is_deeply($statement->[4], ['vrf_domains A', 'joined with A by vrf_domains'], 'direct then brought') or diag explain $statement;
};

done_testing;
