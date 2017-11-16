package App::Netdisco::Util::SNMP;

use Dancer qw/:syntax :script/;
use App::Netdisco::Util::DNS 'hostname_from_ip';
use App::Netdisco::Util::Permission ':all';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  fixup_device_auth get_communities snmp_comm_reindex
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::SNMP

=head1 DESCRIPTION

Helper functions for L<SNMP::Info> instances.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 fixup_device_auth

Rebuilds the C<device_auth> config with missing defaults and other fixups for
config changes over time. Returns a list which can replace C<device_auth>.

=cut

sub fixup_device_auth {
  my $config = (setting('device_auth') || setting('snmp_auth') || []);
  my @new_stanzas = ();

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
    $stanza->{read} = 1 if !exists $stanza->{read};
    $stanza->{no}   ||= [];
    $stanza->{only} ||= ['any'];

    die "error: config: snmpv2 community in device_auth must be single item, not list\n"
      if ref $stanza->{community};

    die "error: config: stanza in device_auth must have a tag\n"
      if not $stanza->{tag} and exists $stanza->{user};

    push @new_stanzas, $stanza
  }

  # legacy config 
  # note: read strings tried before write
  # note: read-write is no longer used for read operations

  push @new_stanzas, map {{
    read => 1, write => 0,
    no => [], only => ['any'],
    community => $_,
  }} @{setting('community') || []};

  push @new_stanzas, map {{
    write => 1, read => 0,
    no => [], only => ['any'],
    community => $_,
  }} @{setting('community_rw') || []};

  foreach my $stanza (@new_stanzas) {
    $stanza->{driver} ||= 'snmp'
      if exists $stanza->{community}
         or exists $stanza->{user};
  }

  return @new_stanzas;
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
  push @communities, _get_external_community($device, $mode)
    if setting('get_community') and length setting('get_community');

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

sub _get_external_community {
  my ($device, $mode) = @_;
  my $cmd = setting('get_community');
  my $ip = $device->ip;
  my $host = ($device->dns || hostname_from_ip($ip) || $ip);

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
                    only => [$device->ip],
                    community => $_,
                  }} split(m/\s*,\s*/,$1);
              }
          }
          elsif ($line =~ m/^setCommunity\s*=\s*(.*)\s*$/i) {
              if (length $1 and $mode eq 'write') {
                  return map {{
                    write => 1,
                    only => [$device->ip],
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

Passing VLAN "C<0>" (zero) will reset the indexing to the basic v2 community
or v3 empty context.

=cut

sub snmp_comm_reindex {
  my ($snmp, $device, $vlan) = @_;
  my $ver = $snmp->snmp_ver;

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

      debug
        sprintf '[%s] reindexing to "%s%s" (ver: %s, class: %s)',
        $device->ip, $prefix, $vlan, $ver, $snmp->class;
      $vlan ? $snmp->update(Context => ($prefix . $vlan))
            : $snmp->update(Context => '');
  }
  else {
      my $comm = $snmp->snmp_comm;

      debug sprintf '[%s] reindexing to vlan %s (ver: %s, class: %s)',
        $device->ip, $vlan, $ver, $snmp->class;
      $vlan ? $snmp->update(Community => $comm . '@' . $vlan)
            : $snmp->update(Community => $comm);
  }
}

true;
