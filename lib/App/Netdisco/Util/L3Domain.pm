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
  l3_domain_recompute_needed
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

A domain is a set of VRF instances (one per device) that form one routing
network. Each VRF is keyed by the first evidence it has, in this order:

=over 4

=item 1. manual

A C<vrf_domains> entry places it. Key C<manual:E<lt>domainE<gt>>.

=item 2. L3 I-SID

Key C<isid:E<lt>nE<gt>>. VRFs with the same L3 I-SID share a domain.

=item 3. route targets

Key C<rt:E<lt>importsE<gt>/E<lt>exportsE<gt>>. VRFs join only when their
de-duplicated, sorted import and export sets are identical and at least one is
non-empty. Hub, shared-services and extranet VRFs have different sets, so they
never bridge customers. An identical route distinguisher is not evidence: the
VRF Naming Inconsistencies report lists it as a hint.

=item 4. name

Key C<name:E<lt>vrfE<gt>>. The same name joins only VRFs that have neither an
I-SID nor route targets.

=back

The key is stored in C<l3_domain.inferred_name>. A domain's display C<name> is
its most common member VRF name (ties go to the alphabetically first), or the
configured name for a manual domain. The default table (C<vrf = ''>) is domain
0 and never has a key or member rows.

The C<vrf_domains> setting is a flat list of entries, each C<< { domain,
device, vrf, join } >>:

  vrf_domains:
    - domain: CUSTOMER-A
      device: 192.0.2.1
      vrf: blue
      join: true                # brings in every VRF sharing blue's key
    - domain: CUSTOMER-A
      device: 192.0.2.10
      vrf: RED-LITE             # a plain entry moves just this VRF
    - domain: CUSTOMER-A
      device: group:branch-ces  # every router in a host_groups group
      vrf: RED-LITE

When entries place one VRF more than once, the most specific wins: an IP
entry, then a C<group:> entry, then a VRF brought in by another entry's
C<join: true>. So a VRF can be split out even from inside a joined domain or a
group. Within one level the alphabetically first domain name wins, with a
warning. A C<join: true> entry still brings in its VRF's partners when another
entry takes that VRF itself, so splitting a joined VRF out leaves its partners
where they were, unless entries place them too.

A C<group:> device is matched live with C<acl_matches_only> at every
recompute. A group that holds a hostname or regular expression rule, directly
or through another C<group:>, is refused with a warning: the ACL matcher
answers such a rule with an uncached DNS lookup per device, and the recompute
runs on every discover, so a large group with slow DNS would add minutes to
each one. A cron rule is refused too, as it makes membership depend on the time
of day. Address, prefix, range, C<prop:>, C<tag:>, C<cf:>, C<group:> and
C<op:and> rules are allowed.

The entries are read through one function, C<manual_l3_entries>, so a table
could supply them later without any other change to the recompute.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 l3_domain_evidence_sql()

Returns a SQL SELECT over C<device_vrf> (named VRFs only) yielding C<ip>,
C<vrf>, C<key>, C<reason> and C<display>. The C<key> is the first evidence the
VRF has: C<isid:E<lt>nE<gt>> for an L3 I-SID, then
C<rt:E<lt>importsE<gt>/E<lt>exportsE<gt>> when it has any route targets (each
set de-duplicated and sorted, ignoring NULL and empty elements, so order and
repeats do not matter), then
C<name:E<lt>vrfE<gt>>. A route-target key longer than 200 bytes is replaced by
C<rt:md5:E<lt>digestE<gt>> of its full text, because the key is in a unique
btree index that a few hundred route targets would overflow; equal sets still
give equal keys. C<reason> is the text stored on the member and
C<display> is the VRF name, for naming the domain.

=head2 manual_l3_entries( [$schema] )

Returns the entries of the C<vrf_domains> setting that are valid, as an
arrayref of C<< { domain, device, vrf, join } >>. Each entry is one future row
of a manual-domain table, which is why the setting is a flat list:

  vrf_domains:
    - domain: CUSTOMER-A
      device: 192.0.2.1         # a PE: bring its whole L3VPN domain
      vrf: blue
      join: true
    - domain: CUSTOMER-A
      device: 192.0.2.10        # the VRF-lite CE: move just this VRF
      vrf: RED-LITE
    - domain: CUSTOMER-A
      device: group:branch-ces  # every CE in a named group
      vrf: RED-LITE

C<device> is one full IP address of any interface of a known device (short
forms such as C<10.1> are refused), returned as the device's canonical IP (all
addresses are resolved in one query, by the rule C<get_device> uses), or exactly
one C<group:E<lt>nameE<gt>> from C<host_groups>, returned unchanged. C<join> is false unless set. An entry that
is malformed, names an unknown device, or names a group that is not cheap to
match is skipped with a warning that says what to change. A group is matched
against every candidate device on every recompute, so it (and every group it
reaches through C<group:>, negated or not) may hold only these rules: an
address, a prefix, a range, C<prop:>, C<tag:>, C<cf:>, C<group:> and
C<op:and>. A hostname or regular expression rule would cost a DNS lookup per
device, and a cron rule makes membership depend on the time of day, so a group
holding one is refused. A group whose C<group:> references form any cycle is
refused too. Returns C<[]> without querying when the setting is empty.

=head2 manual_l3_members( $schema, \@entries, [$evidence] )

Returns the (ip, vrf) pairs the entries place, as an arrayref of
C<< { ip, vrf, domain, level, direct } >>. An entry places the VRF on its
device (or on each device in its group that has that VRF in C<device_vrf>),
and a C<join> entry also places every VRF sharing the evidence key of the VRF
it placed, with C<direct> false. C<level> is C<ip>, C<group> or C<join>, the
order that decides a pair claimed twice (an IP entry, then a group entry, then
a joined VRF); within a level the alphabetically first domain wins, with a
warning. An entry whose VRF is not in C<device_vrf> places nothing and logs
nothing; it takes effect once the device reports that VRF.

=head2 recompute_l3_domains( $schema )

Brings the members of C<l3_domain_member> into line with C<device_vrf> and the
C<vrf_domains> setting. A VRF placed by a manual entry (see
C<manual_l3_members>) is a C<manual> member of the domain keyed
C<manual:E<lt>domainE<gt>>, named as configured. Every other VRF other than
the default table joins the domain of its evidence key (see
C<l3_domain_evidence_sql>), as an C<inferred> member. Domains are matched on
C<inferred_name>, which is unique; C<name> is for display and may repeat. An
inferred domain is named after its most common member VRF name, ties going to
the alphabetically first. The recompute owns the manual rows: it writes them to
match the entries, so removing an entry, or its VRF leaving C<device_vrf>,
returns the VRF to inference at the next recompute. Domains other than 0 left
with no members are deleted. A domain keeps its id across recomputes while its
key is in use.

The recompute is one SQL statement, so the evidence query, the expensive
part, runs once and no temporary table is made. (Placing manual entries runs
the same query filtered to the VRF names or keys they name.) Only what changed
is written. An unchanged network and setting write nothing.

Runs in one transaction under C<with_l3_domain_lock>. Returns the number of
member rows inserted plus deleted plus domains renamed or deleted, so 0 means everything
was already right. Discover calls it once per device, after the transaction
that refreshes C<device_vrf> commits, when C<l3_domain_recompute_needed> says so.

=cut

# COLLATE "C": byte order decides the key on every server, whatever its
# locale or glibc version
# NULL and empty elements are dropped so a VRF holding only those has no
# route targets, instead of every such VRF keying as 'rt:/'
my $_clean_set = sub {
  my $column = shift;
  return qq{ARRAY(SELECT DISTINCT x COLLATE "C" FROM unnest($column) x WHERE x IS NOT NULL AND x <> '' ORDER BY x COLLATE "C")};
};

# A long key would overflow the btree behind the unique index on
# l3_domain.inferred_name (about 230 route targets), which would stop every
# recompute, so a key over 200 bytes is replaced by a digest of its full text.
# Each LATERAL step is fenced with OFFSET 0 so that its arrays are cleaned
# once per row, not once per use.
sub l3_domain_evidence_sql {
  my $imports = $_clean_set->('d.rt_import');
  my $exports = $_clean_set->('d.rt_export');

  return qq{SELECT d.ip, d.vrf,
    CASE WHEN d.l3_isid IS NOT NULL THEN 'isid:' || d.l3_isid
         WHEN t.has_rt THEN CASE WHEN octet_length(k.rtkey) > 200 THEN 'rt:md5:' || md5(k.rtkey) ELSE k.rtkey END
         ELSE 'name:' || d.vrf END AS key,
    CASE WHEN d.l3_isid IS NOT NULL THEN 'shared L3 I-SID ' || d.l3_isid
         WHEN t.has_rt THEN 'same route targets import ' || t.imports || ' export ' || t.exports
         ELSE 'same name ' || d.vrf END AS reason,
    d.vrf AS display
  FROM device_vrf d
  CROSS JOIN LATERAL (SELECT $imports AS imp, $exports AS exp OFFSET 0) s
  CROSS JOIN LATERAL (SELECT array_to_string(s.imp, ',') AS imports, array_to_string(s.exp, ',') AS exports,
    coalesce(array_length(s.imp, 1), 0) + coalesce(array_length(s.exp, 1), 0) > 0 AS has_rt OFFSET 0) t
  CROSS JOIN LATERAL (SELECT 'rt:' || t.imports || '/' || t.exports AS rtkey OFFSET 0) k
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

# Rules a group may hold when vrf_domains uses it. The recompute matches the
# group against every candidate device on every discover, so a rule that makes
# check_acl resolve DNS (a hostname, or a regex) or read the clock (cron) is
# refused. Mirrors the order of tests in Permission.pm's check_acl.
sub _rule_is_cheap {
  my $rule = shift;
  return 0 if !defined $rule or ref $rule;
  $rule =~ s/^!//;
  return 1 if $rule eq 'op:and' or $rule =~ m/^(?:group|tag|cf):./;
  return 1 if $rule =~ m/^([^:]+):/ and $1 !~ m/^[a-f0-9]+$/i;
  return 1 if $rule =~ m/^\d{1,3}(?:\.\d{1,3}){3}-\d{1,3}$/;
  return 1 if $rule =~ m/^[0-9a-f]*:[0-9a-f:]*:[0-9a-f]+-[0-9a-f]+$/i;
  return 1 if $rule =~ m/^\d{1,3}(?:\.\d{1,3}){0,3}(?:\/\d{1,2})?$/;
  return 1 if $rule =~ m/^[0-9a-f:.]*:[0-9a-f:.]*(?:\/\d{1,3})?$/i;
  return 0;
}

# the first group (named, or reached through group:) holding a refused rule,
# as (group, rule)
sub _group_with_refused_rule {
  my ($name, $groups, $seen) = @_;
  return () if $seen->{$name}++;
  my $rules = $groups->{$name};
  for my $rule (ref $rules eq 'ARRAY' ? @$rules : ($rules)) {
    next unless defined $rule;
    return ($name, $rule) unless _rule_is_cheap($rule);
    next unless $rule =~ m/^!?group:(.+)$/;
    my @found = _group_with_refused_rule($1, $groups, $seen);
    return @found if @found;
  }
  return ();
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
  my ($holder, $rule) = _group_with_refused_rule($name, $groups, {});
  return undef unless defined $holder;
  my $shown = ref $rule ? 'a regular expression' : "'$rule'";
  return "group:$holder has the rule $shown, which would need a DNS lookup (or the clock) for every device on every recompute. "
       . "Rebuild that group from addresses, prefixes, ranges, prop:, tag:, cf: or group: rules";
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
  my ($dbh, $entries, $evidence) = @_;
  my %names = map { ($_->{vrf} => 1) } @$entries;
  my $rows = $dbh->selectall_arrayref(
    qq{SELECT host(e.ip) AS ip, e.vrf, e.key FROM $evidence e WHERE e.vrf = ANY(?)},
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
  my ($dbh, $direct_claims, $evidence) = @_;
  my %keys_for_entry;
  for my $claim (grep { $_->{entry}{join} } @$direct_claims) {
    $keys_for_entry{ $claim->{entry}{domain} }{ $claim->{row}{key} } = $claim->{entry};
  }
  return [] unless %keys_for_entry;

  my %keys = map { ($_ => 1) } map { keys %$_ } values %keys_for_entry;
  my $rows = $dbh->selectall_arrayref(
    qq{SELECT host(e.ip) AS ip, e.vrf, e.key FROM $evidence e WHERE e.key = ANY(?)},
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
  my ($schema, $entries, $evidence) = @_;
  return [] unless $entries and @$entries;
  $evidence ||= '(' . l3_domain_evidence_sql() . ')';

  my $members = [];
  $schema->storage->dbh_do(sub {
    my (undef, $dbh) = @_;
    my $direct = _direct_claims($dbh, $entries, _vrf_rows($dbh, $entries, $evidence));
    $members = _pick_winners([ @$direct, @{ _join_claims($dbh, $direct, $evidence) } ]);
  });
  return $members;
}

# One statement, not temporary tables plus separate writes: the temporary
# tables cost catalog rows and WAL on every recompute, unchanged ones included.
# That version (commit bb754463) was somewhat faster on fresh planner
# statistics; revisit it if the time this holds the lock becomes a bottleneck.
# Every CTE reads the snapshot taken before any of them writes, so a member is
# deleted, moved or added, never two of them, and a domain made here is named
# on insert, since no other CTE can see it through l3_domain. desired is read
# by several CTEs, so the server computes it, and the evidence, once.
# Four placeholders: ip, vrf, key and reason arrays of the manual set.
sub _sync_sql {
  my $evidence = l3_domain_evidence_sql();
  return qq{WITH man AS (SELECT * FROM unnest(?::inet[], ?::text[], ?::text[], ?::text[]) AS man(ip, vrf, key, reason)),
  desired AS (
    SELECT man.ip, man.vrf, man.key, man.reason, substr(man.key, 8) AS display, 'manual'::text AS source FROM man
    UNION ALL
    SELECT e.ip, e.vrf, e.key, e.reason, e.display, 'inferred'::text AS source FROM ($evidence) e
    WHERE NOT EXISTS (SELECT 1 FROM man WHERE man.ip = e.ip AND man.vrf = e.vrf)),
  named AS (
    SELECT DISTINCT ON (d.key) d.key, CASE WHEN d.key LIKE 'manual:%' THEN min(d.display) ELSE d.vrf END AS name
    FROM desired d GROUP BY d.key, d.vrf
    ORDER BY d.key, count(*) DESC, d.vrf COLLATE "C"),
  new_dom AS (
    INSERT INTO l3_domain (name, inferred_name)
    SELECT n.name, n.key FROM named n WHERE NOT EXISTS (SELECT 1 FROM l3_domain x WHERE x.inferred_name = n.key)
    RETURNING id, inferred_name),
  dom AS (
    SELECT id, inferred_name FROM l3_domain WHERE inferred_name IS NOT NULL
    UNION ALL SELECT id, inferred_name FROM new_dom),
  target AS (
    SELECT d.ip, d.vrf, m.id AS domain_id, d.reason, d.source FROM desired d JOIN dom m ON m.inferred_name = d.key),
  gone AS (
    DELETE FROM l3_domain_member m WHERE NOT EXISTS (SELECT 1 FROM desired d WHERE d.ip = m.ip AND d.vrf = m.vrf)
    RETURNING 1),
  moved AS (
    UPDATE l3_domain_member m SET domain_id = t.domain_id, reason = t.reason, source = t.source
    FROM target t WHERE t.ip = m.ip AND t.vrf = m.vrf
      AND (t.domain_id <> m.domain_id OR t.reason IS DISTINCT FROM m.reason OR t.source <> m.source)
    RETURNING 1),
  added AS (
    INSERT INTO l3_domain_member (ip, vrf, domain_id, reason, source)
    SELECT t.ip, t.vrf, t.domain_id, t.reason, t.source FROM target t
    WHERE NOT EXISTS (SELECT 1 FROM l3_domain_member m WHERE m.ip = t.ip AND m.vrf = t.vrf)
    RETURNING 1),
  renamed AS (
    UPDATE l3_domain l SET name = n.name FROM named n
    WHERE l.inferred_name = n.key AND l.name IS DISTINCT FROM n.name AND l.inferred_name NOT LIKE 'manual:%'
    RETURNING 1),
  emptied AS (
    DELETE FROM l3_domain l WHERE l.id <> 0 AND NOT EXISTS (SELECT 1 FROM desired d WHERE d.key = l.inferred_name)
    RETURNING 1)
  SELECT (SELECT count(*) FROM gone) + 2 * (SELECT count(*) FROM moved)
       + (SELECT count(*) FROM added) + (SELECT count(*) FROM renamed)
       + (SELECT count(*) FROM emptied)};
}

sub _manual_arrays {
  my $members = shift;
  my @keys = map { 'manual:' . $_->{domain} } @$members;
  my @reasons = map { $_->{direct} ? "vrf_domains $_->{domain}" : "joined with $_->{domain} by vrf_domains" } @$members;
  return ([ map { $_->{ip} } @$members ], [ map { $_->{vrf} } @$members ], \@keys, \@reasons);
}

# a moved member counts twice, as the delete and insert it replaces
sub recompute_l3_domains {
  my $schema = shift;
  my $written = 0;

  with_l3_domain_lock($schema, sub {
    $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      my $members = manual_l3_members($schema, manual_l3_entries($schema));
      ($written) = $dbh->selectrow_array(_sync_sql(), undef, _manual_arrays($members));
    });
  });

  return $written;
}

=head2 l3_domain_recompute_needed( $schema, $device_changed, $by_arpnip? )

True when a caller that has just refreshed one device's C<device_vrf> rows
should run C<recompute_l3_domains>, false when the recompute would find
nothing to change. It is true when any of these holds:

=over 4

=item 1. C<$device_changed> is true

The caller found that the device's evidence changed (VRFs added or removed
count). No SQL runs.

=item 2. C<vrf_domains> is set (not for arpnip)

Any non-empty value, a malformed one included, so that the recompute warns
about it. Group membership can change with no device change, so a configured
site recomputes every time.

=item 3. C<l3_domain_member> holds a C<manual> row (not for arpnip)

This covers removing the last C<vrf_domains> entry.

=item 4. a domain other than 0 has an C<inferred_name> with none of the key prefixes, or none

A key from before the evidence keys, which was the bare VRF name, and a VRF
name may hold a C<:>. One cheap query re-keys it.

=item 5. a named C<device_vrf> row has no C<l3_domain_member> row

=item 6. an C<l3_domain_member> row has no C<device_vrf> row

Both are primary-key anti-joins. They make a failed recompute that left rows
unplaced be retried by the next discover anywhere.

=item 7. a domain other than 0 has no member

Deleting a device removes its C<device_vrf> and member rows together, so
neither 5 nor 6 fires. The next discover anywhere then deletes the empty
domain. It is checked last, as the most expensive.

=back

Arpnip passes C<$by_arpnip>. It runs hourly, so it leaves 2 and 3 to the
device's daily discover, which picks up a C<vrf_domains> or group membership
change.

An evidence change on another device is recomputed by that device's own
discover. A failed recompute after a pure route-target or I-SID change (no VRF
added or removed) stays stale until the next change. So does the display name of a domain that
lost members to a device delete but still has some (cosmetic).

=cut

# any non-empty value counts, whatever its type: a malformed one must reach the
# recompute, which warns that the setting is ignored
sub _vrf_domains_is_set {
  my $entries = shift;
  return 0 unless defined $entries;
  return scalar(@$entries) ? 1 : 0 if ref $entries eq 'ARRAY';
  return scalar(keys %$entries) ? 1 : 0 if ref $entries eq 'HASH';
  return length($entries) ? 1 : 0;
}

sub l3_domain_recompute_needed {
  my ($schema, $device_changed, $by_arpnip) = @_;
  return 1 if $device_changed;
  return 1 if not $by_arpnip and _vrf_domains_is_set(setting('vrf_domains'));

  return $schema->storage->dbh_do(sub {
    my (undef, $dbh) = @_;
    $dbh->selectrow_array($_) and return 1 for _recompute_needed_sql($by_arpnip);
    return 0;
  });
}

# cheapest first, and the caller stops at the first true
sub _recompute_needed_sql {
  my $by_arpnip = shift;
  return (
    ($by_arpnip ? () : q{SELECT EXISTS (SELECT 1 FROM l3_domain_member WHERE source = 'manual')}),
    q{SELECT EXISTS (SELECT 1 FROM l3_domain
      WHERE id <> 0 AND (inferred_name IS NULL OR inferred_name !~ '^(isid|rt|name|manual):'))},
    q{SELECT EXISTS (SELECT 1 FROM device_vrf d WHERE d.vrf <> ''
      AND NOT EXISTS (SELECT 1 FROM l3_domain_member m WHERE m.ip = d.ip AND m.vrf = d.vrf))},
    q{SELECT EXISTS (SELECT 1 FROM l3_domain_member m WHERE NOT EXISTS
      (SELECT 1 FROM device_vrf d WHERE d.ip = m.ip AND d.vrf = m.vrf))},
    q{SELECT EXISTS (SELECT 1 FROM l3_domain d WHERE d.id <> 0
      AND NOT EXISTS (SELECT 1 FROM l3_domain_member m WHERE m.domain_id = d.id))},
  );
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
