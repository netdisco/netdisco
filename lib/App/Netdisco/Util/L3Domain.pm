package App::Netdisco::Util::L3Domain;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  recompute_l3_domains
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

=head2 recompute_l3_domains( $schema )

Rebuilds the inferred members of C<l3_domain_member> from C<device_vrf>: every
VRF name other than the default table joins the domain of that name, which is
created if it does not exist. Domains are matched on C<inferred_name>, which is
unique; C<name> is for display and may repeat. Manual members are never
changed, and a VRF that has a manual member is not inferred. Domains other than
0 left with no members are deleted. A domain keeps its id across recomputes
while its name is in use.

Runs in one transaction under an advisory lock. Returns the number of inferred
members written. Discover calls it once per device, after the transaction that
refreshes C<device_vrf> commits.

Every writer of C<l3_domain> or C<l3_domain_member> must take
C<pg_advisory_xact_lock(1729, 0)> in its transaction first, so that it does not
interleave with a recompute.

=cut

sub recompute_l3_domains {
  my $schema = shift;
  my $written = 0;

  $schema->txn_do(sub {
    $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->do('SELECT pg_advisory_xact_lock(?, ?)', undef, $L3_DOMAIN_LOCK_CLASS, 0);

      $dbh->do(q{DELETE FROM l3_domain_member WHERE source = 'inferred'});

      $dbh->do(q{INSERT INTO l3_domain (name, inferred_name)
        SELECT DISTINCT d.vrf, d.vrf FROM device_vrf d
        WHERE d.vrf <> ''
          AND NOT EXISTS (SELECT 1 FROM l3_domain x WHERE x.inferred_name = d.vrf)});

      $written = $dbh->do(q{INSERT INTO l3_domain_member (ip, vrf, domain_id, reason, source)
        SELECT d.ip, d.vrf, l.id, 'same name ' || d.vrf, 'inferred'
        FROM device_vrf d
        JOIN l3_domain l ON l.inferred_name = d.vrf
        WHERE d.vrf <> ''
          AND NOT EXISTS (SELECT 1 FROM l3_domain_member m
            WHERE m.ip = d.ip AND m.vrf = d.vrf AND m.source = 'manual')});

      $dbh->do(q{DELETE FROM l3_domain
        WHERE id <> 0
          AND NOT EXISTS (SELECT 1 FROM l3_domain_member m WHERE m.domain_id = l3_domain.id)});
    });
  });

  return ($written eq '0E0' ? 0 : $written);
}

=head2 results_span_domains( \@rows )

True when the report rows, each carrying C<vrf> (its domain's name), hold more
than one domain. Reports show a VRF column only then, so that a network with
one domain sees the same report as before.

=cut

sub results_span_domains {
  my $rows = shift;
  my %names = map { (($_->{vrf} // '') => 1) } @$rows;
  return scalar(keys %names) > 1;
}

=head2 label_rows_by_domain( \@rows, $multi_domain )

Returns copies of the report rows shaped for a table rendered in the browser.
With more than one domain, C<vrf> is kept and the default table's empty name
reads "default". With one domain, C<vrf> is dropped, so the page is the same as
before domains.

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
