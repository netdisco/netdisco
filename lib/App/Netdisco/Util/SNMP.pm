package App::Netdisco::Util::SNMP;

use Dancer qw/:syntax :script/;
use App::Netdisco::Util::DeviceAuth 'get_external_credentials';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  get_communities
  snmp_comm_reindex
  sortable_oid
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::SNMP

=head1 DESCRIPTION

Helper functions for L<SNMP::Info> instances.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 sortable_oid( $oid, $seglen? )

Take an OID and return a version of it which is sortable using C<cmp>
operator. Works by zero-padding the numeric parts all to be length
C<< $seglen >>, which defaults to 6.

=cut

# take oid and make comparable
sub sortable_oid {
  my ($oid, $seglen) = @_;
  $seglen ||= 6;
  return $oid if $oid !~ m/^[0-9.]+$/;
  $oid =~ s/^(\.)//; my $leading = $1;
  $oid = join '.', map { sprintf("\%0${seglen}d", $_) } (split m/\./, $oid);
  return (($leading || '') . $oid);
}

=head2 get_communities( $device, $mode )

Takes the current C<device_auth> setting and pushes onto the front of the list
the last known good SNMP settings used for this mode (C<read> or C<write>).

=cut

sub get_communities {
  my ($device, $mode) = @_;
  $mode ||= 'read';

  my $seen_tags = {}; # for cleaning community table
  my $config = (setting('device_auth') || []);
  my @communities = ();

  # first of all, use external command if configured
  push @communities, get_external_credentials($device, $mode);

  # last known-good by tag
  my $tag_name = 'snmp_auth_tag_'. $mode;
  my $stored_tag = eval { $device->community->$tag_name };

  if ($device->in_storage and $stored_tag) {
    foreach my $stanza (@$config) {
      if ($stanza->{tag} and $stored_tag eq $stanza->{tag}) {
        push @communities, {%$stanza, only => [$device->ip]};
        last;
      }
    }
  }

  # try last-known-good v2 read
  push @communities, {
    read => 1, write => 0, driver => 'snmp',
    only => [$device->ip],
    community => $device->snmp_comm,
  } if defined $device->snmp_comm and $mode eq 'read';

  # try last-known-good v2 write
  my $snmp_comm_rw = eval { $device->community->snmp_comm_rw };
  push @communities, {
    write => 1, read => 0, driver => 'snmp',
    only => [$device->ip],
    community => $snmp_comm_rw,
  } if $snmp_comm_rw and $mode eq 'write';

  # clean the community table of obsolete tags
  eval { $device->community->update({$tag_name => undef}) }
    if $device->in_storage
       and (not $stored_tag or !exists $seen_tags->{ $stored_tag });

  return ( @communities, @$config );
}

=head2 snmp_comm_reindex( $snmp, $device, $vlan )

Takes an established L<SNMP::Info> instance and makes a fresh connection using
community indexing, with the given C<$vlan> ID. Works for all SNMP versions.

Inherits the C<vtp_version> from the previous L<SNMP::Info> instance.

Passing VLAN "C<0>" (zero) will reset the indexing to the basic v2 community
or v3 empty context.

=cut

sub snmp_comm_reindex {
  my ($snmp, $device, $vlan) = @_;
  my $ver = $snmp->snmp_ver;
  my $vtp = $snmp->vtp_version;

  if ($ver == 3) {
      my $prefix = '';
      my @comms = get_communities($device, 'read');
      # find a context prefix configured by the user
      foreach my $c (@comms) {
          next unless $c->{tag}
            and $c->{tag} eq (eval { $device->community->snmp_auth_tag_read } || '');
          $prefix = $c->{context_prefix} and last;
      }
      $prefix ||= 'vlan-';

      if ($vlan =~ /^[0-9]+$/i && $vlan) {
        debug sprintf '[%s] reindexing to "%s%s" (ver: %s, class: %s)',
        $device->ip, $prefix, $vlan, $ver, $snmp->class;
        $snmp->update(Context => ($prefix . $vlan));
      } elsif ($vlan =~ /^[a-z0-9]+$/i && $vlan) {
        debug sprintf '[%s] reindexing to "%s" (ver: %s, class: %s)',
          $device->ip, $vlan, $ver, $snmp->class;
        $snmp->update(Context => ($vlan));
      } else {
        debug sprintf '[%s] reindexing without context (ver: %s, class: %s)',
          $device->ip, $ver, $snmp->class;
        $snmp->update(Context => '');
      }
  }
  else {
      my $comm = $snmp->snmp_comm;

      debug sprintf '[%s] reindexing to vlan %s (ver: %s, class: %s)',
        $device->ip, $vlan, $ver, $snmp->class;
      $vlan ? $snmp->update(Community => $comm . '@' . $vlan)
            : $snmp->update(Community => $comm);
  }

  $snmp->cache({ _vtp_version => $vtp });
  return $snmp;
}

true;
