package App::Netdisco::Util::DeviceAuth;

use Dancer qw/:syntax :script/;
use App::Netdisco::Util::DNS 'hostname_from_ip';

use Storable 'dclone';
use Try::Tiny;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  fixup_device_auth get_external_credentials
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::DeviceAuth

=head1 DESCRIPTION

Helper functions for device authentication.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 fixup_device_auth

Rebuilds the C<device_auth> config with missing defaults and other fixups for
config changes over time. Returns a list which can replace C<device_auth>.

=cut

sub fixup_device_auth {
  my $da = dclone (setting('device_auth') || []);
  my $sa = dclone (setting('snmp_auth')   || []);

  die "error: both snmp_auth and device_auth are defined!\n"
    . "move snmp_auth config into device_auth and remove snmp_auth.\n"
    if scalar @$da and scalar @$sa;

  my $config = ((scalar @$da) ? $da : $sa);
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
    $stanza->{only} ||= ['group:__ANY__'];

    die "error: config: snmpv2 community in device_auth must be single item, not list\n"
      if ref $stanza->{community};

    die "error: config: stanza in device_auth must have a tag\n"
      if not $stanza->{tag} and exists $stanza->{user};

    push @new_stanzas, $stanza;
  }

  # import legacy sshcollector configuration
  my @sshcollector = @{ dclone (setting('sshcollector') || []) };
  foreach my $stanza (@sshcollector) {
    # defaults
    $stanza->{driver} = 'cli';
    $stanza->{read} = 1;
    $stanza->{no}   ||= [];

    # fixups
    $stanza->{only} ||= [ scalar delete $stanza->{ip} ||
                          scalar delete $stanza->{hostname} ];
    $stanza->{username} = scalar delete $stanza->{user};

    push @new_stanzas, $stanza;
  }

  # legacy config
  # note: read strings tried before write
  # note: read-write is no longer used for read operations

  push @new_stanzas, map {{
    read => 1, write => 0,
    no => [], only => ['group:__ANY__'],
    community => $_,
  }} @{setting('community') || []};

  push @new_stanzas, map {{
    write => 1, read => 0,
    no => [], only => ['group:__ANY__'],
    community => $_,
  }} @{setting('community_rw') || []};

  foreach my $stanza (@new_stanzas) {
    $stanza->{driver} ||= 'snmp'
      if exists $stanza->{community}
         or exists $stanza->{user};
  }

  return @new_stanzas;
}

=head2 get_external_credentials( $device, $mode )

Runs a command to gather SNMP credentials or a C<device_auth> stanza.

Mode can be C<read> or C<write> and defaults to 'read'.

=cut

sub get_external_credentials {
  my ($device, $mode) = @_;
  my $cmd = (setting('get_credentials') || setting('get_community'));
  my $ip = $device->ip;
  my $host = ($device->dns || hostname_from_ip($ip) || $ip);
  $mode ||= 'read';

  if (defined $cmd and length $cmd) {
      # replace variables
      $cmd =~ s/\%MODE\%/$mode/egi;
      $cmd =~ s/\%HOST\%/$host/egi;
      $cmd =~ s/\%IP\%/$ip/egi;

      my $result = `$cmd`; # BACKTICKS
      return () unless defined $result and length $result;

      my @lines = split (m/\n/, $result);
      foreach my $line (@lines) {
          if ($line =~ m/^community\s*=\s*(.*)\s*$/i) {
              if (length $1 and $mode eq 'read') {
                  debug sprintf '[%s] external read credentials added',
                    $device->ip;

                  return map {{
                    read => 1,
                    only => [$device->ip],
                    community => $_,
                  }} split(m/\s*,\s*/,$1);
              }
          }
          elsif ($line =~ m/^setCommunity\s*=\s*(.*)\s*$/i) {
              if (length $1 and $mode eq 'write') {
                  debug sprintf '[%s] external write credentials added',
                    $device->ip;

                  return map {{
                    write => 1,
                    only => [$device->ip],
                    community => $_,
                  }} split(m/\s*,\s*/,$1);
              }
          }
          else {
            my $stanza = undef;
            try {
              $stanza = from_json( $line );
              debug sprintf '[%s] external credentials stanza added',
                $device->ip;
            }
            catch {
              info sprintf '[%s] error! failed to parse external credentials stanza',
                $device->ip;
            };
            return $stanza if ref $stanza;
          }
      }
  }

  return ();
}

true;
