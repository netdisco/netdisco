package App::Netdisco::Util::L3Domain;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  recompute_l3_domains
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

=head2 recompute_l3_domains( $schema )

Brings the inferred members of C<l3_domain_member> into line with
C<device_vrf>: every VRF other than the default table joins the domain of its
evidence key (see L</l3_domain_evidence_sql>), which is created if it does not
exist. Domains are matched on C<inferred_name>, which is unique; C<name> is for
display and may repeat. A domain not made from a manual setting is named after
its most common member VRF name, ties going to the alphabetically first.
Manual members are never changed, and a VRF that has a manual member is not
inferred. Domains other than 0 left with no members are deleted. A domain keeps
its id across recomputes while its key is in use.

Only what changed is written. An unchanged network writes nothing.

Runs in one transaction under L</with_l3_domain_lock>. Returns the number of
member rows inserted plus deleted plus domains renamed, so 0 means everything
was already right. Discover calls it once per device, after the transaction
that refreshes C<device_vrf> commits.

=cut

sub _rows { my $rows = shift; return ($rows eq '0E0' ? 0 : $rows) }

# NULL and empty elements are dropped so a VRF holding only those has no
# route targets, instead of every such VRF keying as 'rt:/'
my $_clean_set = sub {
  my $column = shift;
  return qq{ARRAY(SELECT DISTINCT x FROM unnest($column) x WHERE x IS NOT NULL AND x <> '' ORDER BY x)};
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

sub _ensure_domains {
  my ($dbh, $evidence) = @_;
  # a key whose pairs are all manual would get a domain the last statement deletes
  return $dbh->do(qq{INSERT INTO l3_domain (name, inferred_name)
    SELECT DISTINCT ON (e.key) e.display, e.key FROM ($evidence) e
    WHERE NOT EXISTS (SELECT 1 FROM l3_domain x WHERE x.inferred_name = e.key)
      AND NOT EXISTS (SELECT 1 FROM l3_domain_member m
        WHERE m.ip = e.ip AND m.vrf = e.vrf AND m.source = 'manual')
    ORDER BY e.key, e.display});
}

sub _delete_stale_members {
  my ($dbh, $evidence) = @_;
  # a manual member shares the (ip, vrf) key, so the source test is what keeps it
  return _rows($dbh->do(qq{DELETE FROM l3_domain_member m
    WHERE m.source = 'inferred'
      AND NOT EXISTS (SELECT 1 FROM ($evidence) e
        JOIN l3_domain l ON l.inferred_name = e.key
        WHERE e.ip = m.ip AND e.vrf = m.vrf AND l.id = m.domain_id)}));
}

sub _insert_members {
  my ($dbh, $evidence) = @_;
  return _rows($dbh->do(qq{INSERT INTO l3_domain_member (ip, vrf, domain_id, reason, source)
    SELECT e.ip, e.vrf, l.id, e.reason, 'inferred'
    FROM ($evidence) e
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
      ORDER BY m.domain_id, count(*) DESC, m.vrf ASC) top
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
    $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      my $evidence = l3_domain_evidence_sql();

      _ensure_domains($dbh, $evidence);
      $written += _delete_stale_members($dbh, $evidence);
      $written += _insert_members($dbh, $evidence);
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
