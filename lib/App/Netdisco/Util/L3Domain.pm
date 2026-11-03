package App::Netdisco::Util::L3Domain;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  recompute_l3_domains
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
created if it does not exist. Manual members are never changed, and a VRF that
has a manual member is not inferred. Domains other than 0 left with no members
are deleted. A domain keeps its id across recomputes while its name is in use.

Runs in one transaction under an advisory lock. Returns the number of inferred
members written. The discover job in 5b-3 will call it after refreshing
C<device_vrf>.

=cut

sub recompute_l3_domains {
  my $schema = shift;
  my $written = 0;

  $schema->txn_do(sub {
    $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->do('SELECT pg_advisory_xact_lock(?, ?)', undef, $L3_DOMAIN_LOCK_CLASS, 0);

      $dbh->do(q{DELETE FROM l3_domain_member WHERE source = 'inferred'});

      $dbh->do(q{INSERT INTO l3_domain (name)
        SELECT DISTINCT d.vrf FROM device_vrf d
        WHERE d.vrf <> ''
          AND NOT EXISTS (SELECT 1 FROM l3_domain x WHERE x.name = d.vrf)});

      $written = $dbh->do(q{INSERT INTO l3_domain_member (ip, vrf, domain_id, reason, source)
        SELECT d.ip, d.vrf, l.id, 'same name ' || d.vrf, 'inferred'
        FROM device_vrf d
        JOIN l3_domain l ON l.name = d.vrf
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

1;
