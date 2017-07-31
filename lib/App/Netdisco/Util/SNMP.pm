package App::Netdisco::Util::SNMP;

use Dancer qw/:syntax :script/;
use App::Netdisco::Util::Permission ':all';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  build_communities snmp_comm_reindex
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::SNMP

=head1 DESCRIPTION

Helper functions for L<SNMP::Info> instances.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 build_communities( $device, $mode )

Takes a Netdisco L<Device|App::Netdisco::DB::Result::Device> instance and
returns a set of potential SNMP community authentication settings that are
configured in Netdisco, for the given mode ("C<read>" or "C<write>").

=cut

sub build_communities {
  my ($device, $mode) = @_;
  $mode ||= 'read';
  my $seen_tags = {}; # for cleaning community table

  my $config = (setting('device_auth') || []);
  my $tag_name = 'snmp_auth_tag_'. $mode;
  my $stored_tag = eval { $device->community->$tag_name };
  my $snmp_comm_rw = eval { $device->community->snmp_comm_rw };
  my @communities = ();

  # try last-known-good read
  push @communities, {read => 1, community => $device->snmp_comm}
    if defined $device->snmp_comm and $mode eq 'read';

  # try last-known-good write
  push @communities, {write => 1, community => $snmp_comm_rw}
    if $snmp_comm_rw and $mode eq 'write';

  # new style snmp config
  foreach my $stanza (@$config) {
      # user tagged
      my $tag = '';
      if (1 == scalar keys %$stanza) {
          $tag = (keys %$stanza)[0];
          $stanza = $stanza->{$tag};

          # corner case: untagged lone community
          if ($tag eq 'community') {
              $tag = $stanza;
              $stanza = {community => $tag};
          }
      }

      # defaults
      $stanza->{tag} ||= $tag;
      ++$seen_tags->{ $stanza->{tag} };
      $stanza->{read} = 1 if !exists $stanza->{read};
      $stanza->{no}   ||= [];
      $stanza->{only} ||= ['any'];
      $stanza->{no}   = [$stanza->{no}] if ref '' eq ref $stanza->{no};
      $stanza->{only} = [$stanza->{only}] if ref '' eq ref $stanza->{only};

      die "error: config: snmpv2 community in device_auth must be single item, not list\n"
        if ref $stanza->{community};

      die "error: config: snmpv3 stanza in device_auth must have a tag\n"
        if not $stanza->{tag}
           and !exists $stanza->{community};

      if ($stanza->{$mode} and check_acl_only($device, $stanza->{only})
            and not check_acl_no($device, $stanza->{no})) {
          if ($device->in_storage and
            $stored_tag and $stored_tag eq $stanza->{tag}) {
              # last known-good by tag
              unshift @communities, $stanza
          }
          else {
              push @communities, $stanza
          }
      }
  }

  # clean the community table of obsolete tags
  if ($stored_tag and !exists $seen_tags->{ $stored_tag }) {
      eval { $device->community->update({$tag_name => undef}) };
  }

  # legacy config (note: read strings tried before write)
  if ($mode eq 'read') {
      push @communities, map {{
        read => 1,
        community => $_,
      }} @{setting('community') || []};
  }
  else {
      push @communities, map {{
        write => 1,
        community => $_,
      }} @{setting('community_rw') || []};
  }

  # but first of all, use external command if configured
  unshift @communities, _get_external_community($device, $mode)
    if setting('get_community') and length setting('get_community');

  return @communities;
}

sub _get_external_community {
  my ($device, $mode) = @_;
  my $cmd = setting('get_community');
  my $ip = $device->ip;
  my $host = $device->dns || $ip;

  if (defined $cmd and length $cmd) {
      # replace variables
      $cmd =~ s/\%HOST\%/$host/egi;
      $cmd =~ s/\%IP\%/$ip/egi;

      my $result = `$cmd`; # BACKTICKS
      return () unless defined $result and length $result;

      my @lines = split (m/\n/, $result);
      foreach my $line (@lines) {
          if ($line =~ m/^community\s*=\s*(.*)\s*$/i) {
              if (length $1 and $mode eq 'read') {
                  return map {{
                    read => 1,
                    community => $_,
                  }} split(m/\s*,\s*/,$1);
              }
          }
          elsif ($line =~ m/^setCommunity\s*=\s*(.*)\s*$/i) {
              if (length $1 and $mode eq 'write') {
                  return map {{
                    write => 1,
                    community => $_,
                  }} split(m/\s*,\s*/,$1);
              }
          }
      }
  }

  return ();
}

=head2 snmp_comm_reindex( $snmp, $device, $vlan )

Takes an established L<SNMP::Info> instance and makes a fresh connection using
community indexing, with the given C<$vlan> ID. Works for all SNMP versions.

=cut

sub snmp_comm_reindex {
  my ($snmp, $device, $vlan) = @_;
  my $ver = $snmp->snmp_ver;

  if ($ver == 3) {
      my $prefix = '';
      my @comms = _build_communities($device, 'read');
      foreach my $c (@comms) {
          next unless $c->{tag}
            and $c->{tag} eq (eval { $device->community->snmp_auth_tag_read } || '');
          $prefix = $c->{context_prefix} and last;
      }
      $prefix ||= 'vlan-';

      debug
        sprintf '[%s] reindexing to "%s%s" (ver: %s, class: %s)',
        $device->ip, $prefix, $vlan, $ver, $snmp->class;
      $snmp->update(Context => ($prefix . $vlan));
  }
  else {
      my $comm = $snmp->snmp_comm;

      debug sprintf '[%s] reindexing to vlan %s (ver: %s, class: %s)',
        $device->ip, $vlan, $ver, $snmp->class;
      $snmp->update(Community => $comm . '@' . $vlan);
  }
}

true;
