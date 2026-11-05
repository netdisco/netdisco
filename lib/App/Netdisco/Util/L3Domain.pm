package App::Netdisco::Util::L3Domain;

use strict;
use warnings;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::Util::Permission 'acl_matches_only';
use NetAddr::IP::Lite;
use Scalar::Util 'blessed';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  recompute_l3_domains
  manual_l3_entries
  manual_l3_members
  l3_domain_evidence_sql
  with_l3_domain_lock
  results_span_domains
  label_rows_by_domain
  row_l3_domain
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

# 1728 is store_arp's class; the recompute is network-wide, so it takes one
# global key
my $L3_DOMAIN_LOCK_CLASS = 1729;

=head1 NAME

App::Netdisco::Util::L3Domain

=head1 DESCRIPTION

Helper subroutines for grouping VRFs into layer 3 domains.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 l3_domain_evidence_sql()

Returns a SQL SELECT over C<device_vrf> (named VRFs only) yielding C<ip>,
C<vrf>, C<key>, C<reason> and C<display>. The C<key> is the first evidence the
VRF has: C<isid:E<lt>nE<gt>> for an L3 I-SID, then
C<rt:E<lt>importsE<gt>/E<lt>exportsE<gt>> when it has any route targets (each
set de-duplicated and sorted, ignoring NULL and empty elements, so order and repeats do not matter), then
C<name:E<lt>vrfE<gt>>. C<reason> is the text stored on the member and
C<display> is the VRF name, for naming the domain.

=head2 manual_l3_entries( [$schema] )

Returns the entries of the C<vrf_domains> setting that are valid, as an
arrayref of C<< { domain, device, vrf, join } >>. Each entry is one future row
of a manual-domain table, which is why the setting is a flat list:

  vrf_domains:
    - domain: CUSTOMER-A
      device: 10.0.0.1          # a PE: bring its whole L3VPN domain
      vrf: blue
      join: true
    - domain: CUSTOMER-A
      device: 192.0.2.10        # the VRF-lite CE: move just this VRF
      vrf: RED-LITE
    - domain: CUSTOMER-A
      device: group:branch-ces  # every CE in a named group
      vrf: RED-LITE

C<device> is the address of any interface of a known device, returned as the
device's canonical IP (all addresses are resolved in one query, by the rule
C<get_device> uses), or exactly one C<group:E<lt>nameE<gt>> from
C<host_groups>, returned unchanged. C<join> is false unless set. An entry that
is malformed, names an unknown device, or names a group holding a regular
expression rule (directly, or through another C<group:>) is skipped with a
warning that says what to change. Returns C<[]> without querying when the
setting is empty.

=head2 manual_l3_members( $schema, \@entries )

Returns the (ip, vrf) pairs the entries place, as an arrayref of
C<< { ip, vrf, domain, level, direct } >>. An entry places the VRF on its
device (or on each device in its group that has that VRF in C<device_vrf>),
and a C<join> entry also places every VRF sharing the evidence key of the VRF
it placed, with C<direct> false. C<level> is C<ip>, C<group> or C<join>, the
order that decides a pair claimed twice (an IP entry, then a group entry, then
a joined VRF); within a level the alphabetically first domain wins, with a
warning. An entry whose VRF is not in C<device_vrf> places nothing.

=head2 recompute_l3_domains( $schema )

Brings the members of C<l3_domain_member> into line with C<device_vrf> and the
C<vrf_domains> setting. A VRF placed by a manual entry (see
L</manual_l3_members>) is a C<manual> member of the domain keyed
C<manual:E<lt>domainE<gt>>, named as configured. Every other VRF other than
the default table joins the domain of its evidence key (see
L</l3_domain_evidence_sql>), as an C<inferred> member. Domains are matched on
C<inferred_name>, which is unique; C<name> is for display and may repeat. An
inferred domain is named after its most common member VRF name, ties going to
the alphabetically first. The recompute owns the manual rows: it writes them to
match the entries, so removing an entry, or its VRF leaving C<device_vrf>,
returns the VRF to inference at the next recompute. Domains other than 0 left
with no members are deleted. A domain keeps its id across recomputes while its
key is in use.

Only what changed is written. An unchanged network and setting write nothing.

Runs in one transaction under L</with_l3_domain_lock>. Returns the number of
member rows inserted plus deleted plus domains renamed, so 0 means everything
was already right. Discover calls it once per device, after the transaction
that refreshes C<device_vrf> commits.

=cut

sub _rows { my $rows = shift; return ($rows eq '0E0' ? 0 : $rows) }

# COLLATE "C": byte order decides the key on every server, whatever its
# locale or glibc version
# NULL and empty elements are dropped so a VRF holding only those has no
# route targets, instead of every such VRF keying as 'rt:/'
my $_clean_set = sub {
  my $column = shift;
  return qq{ARRAY(SELECT DISTINCT x COLLATE "C" FROM unnest($column) x WHERE x IS NOT NULL AND x <> '' ORDER BY x COLLATE "C")};
};

sub l3_domain_evidence_sql {
  my $imports = $_clean_set->('d.rt_import');
  my $exports = $_clean_set->('d.rt_export');
  my $has_rt  = qq{coalesce(array_length($imports, 1), 0) + coalesce(array_length($exports, 1), 0) > 0};
  my ($imports_text, $exports_text) = map { qq{array_to_string($_, ',')} } ($imports, $exports);

  return qq{SELECT d.ip, d.vrf,
    CASE WHEN d.l3_isid IS NOT NULL THEN 'isid:' || d.l3_isid
         WHEN $has_rt THEN 'rt:' || $imports_text || '/' || $exports_text
         ELSE 'name:' || d.vrf END AS key,
    CASE WHEN d.l3_isid IS NOT NULL THEN 'shared L3 I-SID ' || d.l3_isid
         WHEN $has_rt THEN 'same route targets import ' || $imports_text || ' export ' || $exports_text
         ELSE 'same name ' || d.vrf END AS reason,
    d.vrf AS display
  FROM device_vrf d
  WHERE d.vrf <> ''};
}

sub _plain_text {
  my $value = shift;
  return (defined $value and !ref $value and $value ne '') ? $value : undef;
}

sub _as_boolean {
  my $value = shift;
  return 0 if !defined $value or (!ref $value and $value eq '');
  if (ref $value) {
    return undef unless blessed $value and $value->isa('JSON::PP::Boolean');
    return ($value ? 1 : 0);
  }
  return 1 if $value =~ m/^(?:1|true)$/i;
  return 0 if $value =~ m/^(?:0|false)$/i;
  return undef;
}

# strict, because PostgreSQL's inet refuses the short forms NetAddr accepts
# ('10', '10.1') and one refusal would fail the whole batched lookup
sub _is_single_address {
  my $text = shift;
  my $octet = qr/(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])/;
  return 1 if $text =~ m/^$octet(?:\.$octet){3}$/;
  my ($head, $tail) = $text =~ m/^([0-9A-Fa-f:]+?:)([0-9]+(?:\.[0-9]+)+)$/ ? ($1, $2) : ($text, undef);
  return 0 if defined $tail and $tail !~ m/^$octet(?:\.$octet){3}$/;
  return 0 unless $head =~ m/^[0-9A-Fa-f:]+$/ and $text =~ m/:.*:/;
  my $ip = NetAddr::IP::Lite->new($text) or return 0;
  return ($ip->version == 6 and $ip->masklen == 128) ? 1 : 0;
}

sub _describe_entry {
  my $entry = shift;
  my @fields = map {
    my $value = ref $entry eq 'HASH' ? $entry->{$_} : undef;
    "$_ '" . (!defined $value ? '' : ref $value ? 'a ' . lc ref($value) . ' reference' : $value) . "'";
  } qw/domain device vrf/;
  return 'vrf_domains entry (' . join(', ', @fields) . ')';
}

# the first group (named, or reached through group:) holding a regex rule
sub _group_with_regex {
  my ($name, $groups, $seen) = @_;
  return undef if $seen->{$name}++;
  my $rules = $groups->{$name};
  for my $rule (ref $rules eq 'ARRAY' ? @$rules : ($rules)) {
    next unless defined $rule;
    return $name if ref $rule eq ref qr//;
    next if ref $rule or $rule !~ m/^!?group:(.+)$/;
    my $found = _group_with_regex($1, $groups, $seen);
    return $found if defined $found;
  }
  return undef;
}

# returns the normalized entry, or the reason it cannot be used
sub _check_entry {
  my $raw = shift;
  return (undef, 'it is not a mapping. Write it as domain, device, vrf and an optional join')
    if ref $raw ne 'HASH';

  for my $field (qw/domain vrf/) {
    return (undef, "its $field is missing or empty. Set $field to a name")
      unless defined _plain_text($raw->{$field});
    return (undef, "$field 'default' is the default table, which cannot be a manual domain or VRF. Use another $field")
      if lc $raw->{$field} eq 'default';
  }

  my $device = _plain_text($raw->{device});
  return (undef, 'its device must be one IP address or one group:<name>. Set device to the address of any interface of the device, or to a single group from host_groups')
    unless defined $device and ($device =~ m/^group:\S+$/ or _is_single_address($device));

  my $join = _as_boolean($raw->{join});
  return (undef, "its join must be true or false, not '" . (ref $raw->{join} ? 'a ' . lc ref($raw->{join}) . ' reference' : $raw->{join}) . "'. Set join to true or false, or remove it")
    unless defined $join;

  return ({ domain => $raw->{domain}, device => $device, vrf => $raw->{vrf}, join => $join });
}

# the path of group names that leads back to a group already on it, if any
sub _group_cycle {
  my ($name, $groups, $path) = @_;
  my ($at) = grep { $path->[$_] eq $name } 0 .. $#$path;
  return [ @{$path}[$at .. $#$path], $name ] if defined $at;
  my $rules = $groups->{$name};
  for my $rule (ref $rules eq 'ARRAY' ? @$rules : ($rules)) {
    next if !defined $rule or ref $rule or $rule !~ m/^!?group:(.+)$/;
    my $cycle = _group_cycle($1, $groups, [ @$path, $name ]);
    return $cycle if $cycle;
  }
  return undef;
}

sub _entry_group_problem {
  my $entry = shift;
  return undef unless $entry->{device} =~ m/^group:(.+)$/;
  my ($name, $groups) = ($1, setting('host_groups') || {});
  my $cycle = _group_cycle($name, $groups, []);
  return 'host_groups has a cycle (' . join(' -> ', map { "group:$_" } @$cycle)
       . '), which would make the ACL matcher recurse until the worker runs out of memory. Remove one of the group: references'
    if $cycle;
  my $holder = _group_with_regex($name, $groups, {});
  return undef unless defined $holder;
  return "group:$holder has a regular expression rule, which makes every recompute look up reverse DNS per device. "
       . "Rebuild that group from addresses, prefixes, prop: or tag: rules";
}

my $_resolve_sql = q{WITH req AS (SELECT r.input, r.input::inet AS addr FROM unnest(?::text[]) AS r(input))
  SELECT DISTINCT ON (r.input) r.input, host(a.ip) AS ip
  FROM req r
  JOIN (
    SELECT d.ip, d.alias, 0 AS rank FROM device_ip d JOIN req q ON q.addr = d.alias WHERE d.ip = d.alias
    UNION ALL
    SELECT d.ip, d.ip AS alias, 0 AS rank FROM device d JOIN req q ON q.addr = d.ip
    UNION ALL
    SELECT v.ip, v.alias, 1 AS rank FROM device_ip_resolved v JOIN req q ON q.addr = v.alias
  ) a ON a.alias = r.addr
  ORDER BY r.input, a.rank, a.ip};

sub _resolve_addresses {
  my ($schema, $addresses) = @_;
  my %owner;
  $schema->storage->dbh_do(sub {
    my (undef, $dbh) = @_;
    my $rows = $dbh->selectall_arrayref($_resolve_sql, { Slice => {} }, $addresses);
    $owner{ $_->{input} } = $_->{ip} for @$rows;
  });
  return \%owner;
}

sub manual_l3_entries {
  my $schema = shift || schema(vars->{'tenant'});
  my $setting = setting('vrf_domains');
  return [] if !defined $setting or (ref $setting eq 'ARRAY' and !@$setting);

  unless (ref $setting eq 'ARRAY') {
    warning 'vrf_domains is not a list, so every entry in it is ignored. Write it as a list of entries, each with domain, device, vrf and an optional join';
    return [];
  }

  my @valid;
  for my $raw (@$setting) {
    my ($entry, $problem) = _check_entry($raw);
    $problem = _entry_group_problem($entry) if $entry and !$problem;
    if ($problem) {
      warning sprintf '%s is skipped: %s', _describe_entry($raw), $problem;
      next;
    }
    push @valid, $entry;
  }
  return _resolve_entry_devices($schema, \@valid);
}

sub _resolve_entry_devices {
  my ($schema, $entries) = @_;
  my %addresses = map { ($_->{device} => 1) } grep { $_->{device} !~ m/^group:/ } @$entries;
  my $owner = %addresses ? _resolve_addresses($schema, [ sort keys %addresses ]) : {};

  my @resolved;
  for my $entry (@$entries) {
    if ($entry->{device} =~ m/^group:/) { push @resolved, $entry; next }
    my $ip = $owner->{ $entry->{device} };
    if (!defined $ip) {
      warning sprintf '%s is skipped: no discovered device has the address %s. Use the address of an interface of a device Netdisco has discovered',
        _describe_entry($entry), $entry->{device};
      next;
    }
    push @resolved, { %$entry, device => $ip };
  }
  return \@resolved;
}

my %LEVEL_RANK = (ip => 0, group => 1, join => 2);

sub _vrf_rows {
  my ($dbh, $entries) = @_;
  my %names = map { ($_->{vrf} => 1) } @$entries;
  my $rows = $dbh->selectall_arrayref(
    q{SELECT host(e.ip) AS ip, e.vrf, e.key FROM (} . l3_domain_evidence_sql() . q{) e WHERE e.vrf = ANY(?)},
    { Slice => {} }, [ sort keys %names ]);
  my %by_vrf;
  push @{ $by_vrf{ $_->{vrf} } }, $_ for @$rows;
  return \%by_vrf;
}

# the group names that exist, each warned about once per entry that cannot use it
sub _usable_group_entries {
  my $entries = shift;
  my $groups = setting('host_groups') || {};
  my @usable;
  for my $entry (grep { $_->{device} =~ m/^group:/ } @$entries) {
    (my $name = $entry->{device}) =~ s/^group://;
    my $rules = $groups->{$name};
    if (ref $rules eq 'ARRAY' ? !@$rules : !defined $rules) {
      warning sprintf '%s matches nothing: %s is not defined, or is empty, in host_groups. Define it there, or fix the name',
        _describe_entry($entry), $entry->{device};
      next;
    }
    push @usable, $entry;
  }
  return \@usable;
}

sub _device_rows_by_ip {
  my ($dbh, $ips) = @_;
  return {} unless @$ips;
  my $rows = $dbh->selectall_arrayref(q{SELECT * FROM device WHERE ip = ANY(?::inet[])}, { Slice => {} }, $ips);
  return { map { ($_->{ip} => $_) } @$rows };
}

# every (entry, row, level) the entries claim directly
sub _direct_claims {
  my ($dbh, $entries, $by_vrf) = @_;
  my @claims;

  for my $entry (grep { $_->{device} !~ m/^group:/ } @$entries) {
    push @claims, map { { entry => $entry, row => $_, level => 'ip' } }
      grep { $_->{ip} eq $entry->{device} } @{ $by_vrf->{ $entry->{vrf} } || [] };
  }

  my $group_entries = _usable_group_entries($entries);
  my %candidate_ips = map { ($_->{ip} => 1) } map { @{ $by_vrf->{ $_->{vrf} } || [] } } @$group_entries;
  my $devices = _device_rows_by_ip($dbh, [ sort keys %candidate_ips ]);
  for my $entry (@$group_entries) {
    for my $row (@{ $by_vrf->{ $entry->{vrf} } || [] }) {
      my $device = $devices->{ $row->{ip} } or next;
      push @claims, { entry => $entry, row => $row, level => 'group' }
        if acl_matches_only($device, $entry->{device});
    }
  }
  return \@claims;
}

sub _join_claims {
  my ($dbh, $direct_claims) = @_;
  my %keys_for_entry;
  for my $claim (grep { $_->{entry}{join} } @$direct_claims) {
    $keys_for_entry{ $claim->{entry}{domain} }{ $claim->{row}{key} } = $claim->{entry};
  }
  return [] unless %keys_for_entry;

  my %keys = map { ($_ => 1) } map { keys %$_ } values %keys_for_entry;
  my $rows = $dbh->selectall_arrayref(
    q{SELECT host(e.ip) AS ip, e.vrf, e.key FROM (} . l3_domain_evidence_sql() . q{) e WHERE e.key = ANY(?)},
    { Slice => {} }, [ sort keys %keys ]);

  my @claims;
  for my $row (@$rows) {
    for my $domain (sort keys %keys_for_entry) {
      my $entry = $keys_for_entry{$domain}{ $row->{key} } or next;
      push @claims, { entry => $entry, row => $row, level => 'join' };
    }
  }
  return \@claims;
}

# one winner per (ip, vrf): the most specific level, then the first domain name
sub _pick_winners {
  my $claims = shift;
  my %by_pair;
  push @{ $by_pair{ "$_->{row}{ip}\t$_->{row}{vrf}" } }, $_ for @$claims;

  my @members;
  for my $pair (sort keys %by_pair) {
    my @ranked = sort {
      $LEVEL_RANK{ $a->{level} } <=> $LEVEL_RANK{ $b->{level} }
        or $a->{entry}{domain} cmp $b->{entry}{domain}
    } @{ $by_pair{$pair} };
    my $winner = $ranked[0];
    _warn_tied_domains($winner, \@ranked);
    push @members, {
      ip => $winner->{row}{ip}, vrf => $winner->{row}{vrf}, domain => $winner->{entry}{domain},
      level => $winner->{level}, direct => ($winner->{level} eq 'join' ? 0 : 1),
    };
  }
  return \@members;
}

sub _warn_tied_domains {
  my ($winner, $ranked) = @_;
  my %tied = map { ($_->{entry}{domain} => 1) }
    grep { $_->{level} eq $winner->{level} } @$ranked;
  return unless keys %tied > 1;
  warning sprintf 'vrf_domains puts VRF %s on %s in more than one domain at the same level (%s). Using %s, the first by name. Remove the entries for the others',
    $winner->{row}{vrf}, $winner->{row}{ip}, join(', ', sort keys %tied), $winner->{entry}{domain};
}

sub manual_l3_members {
  my ($schema, $entries) = @_;
  return [] unless $entries and @$entries;

  my $members = [];
  $schema->storage->dbh_do(sub {
    my (undef, $dbh) = @_;
    my $direct = _direct_claims($dbh, $entries, _vrf_rows($dbh, $entries));
    $members = _pick_winners([ @$direct, @{ _join_claims($dbh, $direct) } ]);
  });
  return $members;
}

# The desired (ip, vrf, key, reason, display, source) rows: the manual set
# first, then the evidence for every pair the manual set does not claim.
# Four placeholders: ip, vrf, key and reason arrays of the manual set.
sub _desired_sql {
  my $evidence = l3_domain_evidence_sql();
  return qq{WITH man AS (SELECT * FROM unnest(?::inet[], ?::text[], ?::text[], ?::text[]) AS man(ip, vrf, key, reason))
    SELECT man.ip, man.vrf, man.key, man.reason, substr(man.key, 8) AS display, 'manual'::text AS source FROM man
    UNION ALL
    SELECT e.ip, e.vrf, e.key, e.reason, e.display, 'inferred'::text AS source FROM ($evidence) e
    WHERE NOT EXISTS (SELECT 1 FROM man WHERE man.ip = e.ip AND man.vrf = e.vrf)};
}

sub _manual_arrays {
  my $members = shift;
  my @keys = map { 'manual:' . $_->{domain} } @$members;
  my @reasons = map { $_->{direct} ? "vrf_domains $_->{domain}" : "joined with $_->{domain} by vrf_domains" } @$members;
  return ([ map { $_->{ip} } @$members ], [ map { $_->{vrf} } @$members ], \@keys, \@reasons);
}

sub _ensure_domains {
  my $dbh = shift;
  return $dbh->do(qq{INSERT INTO l3_domain (name, inferred_name)
    SELECT DISTINCT ON (e.key) e.display, e.key FROM l3_domain_desired e
    WHERE NOT EXISTS (SELECT 1 FROM l3_domain x WHERE x.inferred_name = e.key)
    ORDER BY e.key, e.display COLLATE "C"});
}

sub _delete_stale_members {
  my $dbh = shift;
  return _rows($dbh->do(qq{DELETE FROM l3_domain_member m
    WHERE NOT EXISTS (SELECT 1 FROM l3_domain_desired e
        JOIN l3_domain l ON l.inferred_name = e.key
        WHERE e.ip = m.ip AND e.vrf = m.vrf AND l.id = m.domain_id)}));
}

sub _insert_members {
  my $dbh = shift;
  return _rows($dbh->do(qq{INSERT INTO l3_domain_member (ip, vrf, domain_id, reason, source)
    SELECT e.ip, e.vrf, l.id, e.reason, e.source
    FROM l3_domain_desired e
    JOIN l3_domain l ON l.inferred_name = e.key
    WHERE NOT EXISTS (SELECT 1 FROM l3_domain_member m
      WHERE m.ip = e.ip AND m.vrf = e.vrf)}));
}

sub _rename_domains {
  my $dbh = shift;
  return _rows($dbh->do(q{UPDATE l3_domain l SET name = top.vrf
    FROM (SELECT DISTINCT ON (m.domain_id) m.domain_id, m.vrf
      FROM l3_domain_member m
      GROUP BY m.domain_id, m.vrf
      ORDER BY m.domain_id, count(*) DESC, m.vrf COLLATE "C" ASC) top
    WHERE top.domain_id = l.id
      AND l.name IS DISTINCT FROM top.vrf
      AND l.inferred_name NOT LIKE 'manual:%'}));
}

sub _delete_empty_domains {
  my $dbh = shift;
  return $dbh->do(q{DELETE FROM l3_domain
    WHERE id <> 0
      AND NOT EXISTS (SELECT 1 FROM l3_domain_member m WHERE m.domain_id = l3_domain.id)});
}

sub recompute_l3_domains {
  my $schema = shift;
  my $written = 0;

  with_l3_domain_lock($schema, sub {
    my @manual = _manual_arrays(manual_l3_members($schema, manual_l3_entries($schema)));
    $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      my $desired = _desired_sql();

      # the evidence keys cost far more than the writes, so compute them once;
      # the DROP covers a second call inside the caller's transaction
      $dbh->do('DROP TABLE IF EXISTS l3_domain_desired');
      $dbh->do("CREATE TEMP TABLE l3_domain_desired ON COMMIT DROP AS $desired", undef, @manual);
      _ensure_domains($dbh);
      $written += _delete_stale_members($dbh);
      $written += _insert_members($dbh);
      $written += _rename_domains($dbh);
      _delete_empty_domains($dbh);
    });
  });

  return $written;
}

=head2 with_l3_domain_lock( $schema, \&code )

Runs C<$code> inside a transaction (joining the caller's, if one is open)
after C<pg_advisory_xact_lock(1729, 0)>, and returns what it returns. Every
writer of C<l3_domain> or C<l3_domain_member> goes through this, so that it
does not interleave with a recompute.

=cut

sub with_l3_domain_lock {
  my ($schema, $code) = @_;
  return $schema->txn_do(sub {
    $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->do('SELECT pg_advisory_xact_lock(?, ?)', undef, $L3_DOMAIN_LOCK_CLASS, 0);
    });
    return $code->();
  });
}

=head2 results_span_domains( \@rows )

True when any of the report rows, each carrying C<vrf> (its domain's name), is
in a named domain; two domains always include one. Reports show a VRF column
only then, so that a network using only the default table sees the same report
as before.

=cut

sub results_span_domains {
  my $rows = shift;
  return scalar grep { ($_->{vrf} // '') ne '' } @$rows;
}

=head2 label_rows_by_domain( \@rows, $multi_domain )

Returns copies of the report rows shaped for a table rendered in the browser.
When C<$multi_domain> is true (any row in a named domain, see
C<results_span_domains>), C<vrf> is kept and the default table's empty name
reads "default". Otherwise every row is in the default table and C<vrf> is
dropped, so the page is the same as before domains.

=cut

sub label_rows_by_domain {
  my ($rows, $multi_domain) = @_;
  return [ map {
    my %row = %$_;
    if ($multi_domain) { $row{vrf} = 'default' if ($row{vrf} // '') eq '' }
    else { delete $row{vrf} }
    \%row;
  } @$rows ];
}

=head2 row_l3_domain( $row, $router )

Returns C<< { id =E<gt> ..., name =E<gt> ... } >> for the L3 domain of a result
row with a C<vrf> column, or undef when the domain cannot be determined. C<$router>
is the address of the device that reported the row (undef when unknown). The
default table is domain 0 without a query. The query runs on the row's own
schema, so tenants work.

=cut

sub row_l3_domain {
  my ($row, $router) = @_;
  return { id => 0, name => '' } if $row->get_column('vrf') eq '';

  my $found;
  $row->result_source->schema->storage->dbh_do(sub {
    my (undef, $dbh) = @_;
    $found = $dbh->selectrow_hashref(
      'SELECT d.id, d.name FROM l3_domain d WHERE d.id = l3_domain_of(?, ?)',
      undef, $router, $row->get_column('vrf'));
  });
  return $found ? { id => $found->{id}, name => $found->{name} } : undef;
}

1;
