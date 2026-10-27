package App::Netdisco::Util::SNMP;

use Dancer qw/:syntax :script/;
use App::Netdisco::Util::DeviceAuth 'get_external_credentials';

use Path::Class 'dir';
use File::Spec::Functions qw/splitdir catdir catfile/;
use MIME::Base64 'decode_base64';
use SNMP::Info;
use JSON::PP ();
use Scalar::Util 'refaddr';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  get_communities
  snmp_comm_reindex
  snmp_vrf_reindex
  get_mibdirs
  get_mibdirs_shortnames
  decode_and_munge
  sortable_oid
  walk_mark
  incomplete_walks
  incomplete_walk_message
  incomplete_walks_for
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::SNMP

=head1 DESCRIPTION

Helper functions for L<SNMP::Info> instances.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

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

  # A hint for a configured tag other than the stored one goes ahead of the
  # last known-good credentials, so that a device answering to both can be
  # moved to the hinted ones, as device_auth_tag_hint is documented to do.
  # The known-good stanza stays in the list behind it, as does every other.
  my $hint = setting('device_auth_tag_hint');
  my $hint_wins = ($hint and $hint ne ($stored_tag // '')
    and scalar grep { $_->{tag} and $_->{tag} eq $hint } @$config);

  if ($device->in_storage and $stored_tag) {
    foreach my $stanza (@$config) {
      if ($stanza->{tag} and $stored_tag eq $stanza->{tag}) {
        push @communities, {%$stanza, only => [$device->ip]}
          unless $hint_wins;
        ++$seen_tags->{ $stored_tag };
        last;
      }
    }
  }

  # try last-known-good v2 read
  push @communities, {
    read => 1, write => 0, driver => 'snmp',
    only => [$device->ip],
    community => $device->snmp_comm,
  } if defined $device->snmp_comm and $mode eq 'read' and not $hint_wins;

  # try last-known-good v2 write
  my $snmp_comm_rw = eval { $device->community->snmp_comm_rw };
  push @communities, {
    write => 1, read => 0, driver => 'snmp',
    only => [$device->ip],
    community => $snmp_comm_rw,
  } if $snmp_comm_rw and $mode eq 'write' and not $hint_wins;

  # clean the community table of obsolete tags
  eval { $device->community->update({$tag_name => undef}) }
    if $device->in_storage
       and (not $stored_tag or !exists $seen_tags->{ $stored_tag });

  return return ( @communities, @$config );
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
  return _reindex($snmp, $device, $vlan, 'vlan');
}

=head2 snmp_vrf_reindex( $snmp, $device, $vrf )

As C<snmp_comm_reindex>, but for a VRF's SNMP context: on SNMPv3 the context
is the VRF name as given, never the VLAN context prefix.

=cut

sub snmp_vrf_reindex {
  my ($snmp, $device, $vrf) = @_;
  return _reindex($snmp, $device, $vrf, 'vrf');
}

sub _reindex {
  my ($snmp, $device, $index, $kind) = @_;
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

      # snmp_comm_reindex has been passed VRF names too, so for a VLAN only
      # a number takes the prefix
      if ($kind eq 'vlan' && $index =~ /^[0-9]+$/ && $index) {
        debug sprintf ' [%s] reindexing to "%s%s" (ver: %s, class: %s)',
        $device->ip, $prefix, $index, $ver, $snmp->class;
        $snmp->update(Context => ($prefix . $index));
      } elsif ($index =~ /^\S+$/ && $index) {
        debug sprintf ' [%s] reindexing to "%s" (ver: %s, class: %s)',
          $device->ip, $index, $ver, $snmp->class;
        $snmp->update(Context => ($index));
      } else {
        debug sprintf ' [%s] reindexing without context (ver: %s, class: %s)',
          $device->ip, $ver, $snmp->class;
        $snmp->update(Context => '');
      }
  }
  else {
      my $comm = $snmp->snmp_comm;

      debug sprintf ' [%s] reindexing to %s %s (ver: %s, class: %s)',
        $device->ip, $kind, $index, $ver, $snmp->class;
      $index ? $snmp->update(Community => $comm . '@' . $index)
             : $snmp->update(Community => $comm);
  }

  $snmp->cache({ _vtp_version => $vtp });
  return $snmp;
}

=head2 get_mibdirs

Return a list of directories in the `netdisco-mibs` folder.

=cut

sub get_mibdirs {
  my $home = (setting('mibhome') || dir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'netdisco-mibs'));
  return map { dir($home, $_)->stringify }
             @{ setting('mibdirs') || get_mibdirs_shortnames() };
}

sub get_mibdirs_shortnames {
  my $home = (setting('mibhome') || dir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'netdisco-mibs'));
  my @list = map {s|$home/||; $_} grep { m|/[a-z0-9-]+$| } grep {-d} glob("$home/*");
  return \@list;
}

=head2 decode_and_munge( $method, $data )

Takes some data from snmpwalk cache that has been Base64 encoded,
decodes it and then munge to handle data format, before finally pretty
render in JSON format.

=cut

sub get_code_info { return ($_[0]) =~ m/^(.+)::(.*?)$/ }
sub sub_name      { return (get_code_info $_[0])[1] }
sub class_name    { return (get_code_info $_[0])[0] }

sub decode_and_munge {
    my ($munger, $encoded) = @_;
    return undef unless defined $encoded and length $encoded;

    my $json = JSON::PP->new->utf8->pretty->allow_nonref->allow_unknown->canonical;
    $json->sort_by( sub { sortable_oid($JSON::PP::a) cmp sortable_oid($JSON::PP::b) } );

    return undef if $encoded !~ m/^\[/; # legacy format double protection for web crash
    my $data = (@{ from_json($encoded) })[0];

    $data = (ref {} eq ref $data)
      ? { map {($_ => (defined $data->{$_} ? decode_base64($data->{$_}) : undef))}
              keys %$data }
      : (defined $data ? decode_base64($data) : undef);

    return $json->encode( $data ) if not $munger;

    # this names a class to load and a sub to call, and reaches here from the
    # request, so only SNMP::Info's own namespace is accepted
    return $json->encode( $data )
      unless $munger =~ m/^SNMP::Info(?:::[A-Za-z0-9_]+)*::[A-Za-z0-9_]+$/;

    my $sub   = sub_name($munger);
    my $class = class_name($munger);
    Module::Load::load $class;

    # munge_e_type seems broken, noop it
    return $json->encode( $data ) if $sub eq 'munge_e_type' and $class eq 'SNMP::Info';

    $data = (ref {} eq ref $data)
      ? { map {($_ => (defined $data->{$_} ? $class->can($sub)->($data->{$_}) : undef))}
              keys %$data }
      : (defined $data ? $class->can($sub)->($data) : undef);

    return $json->encode( $data );
}

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

=head2 walk_mark( $snmp )

Returns the number of incomplete walks the L<SNMP::Info> instance has
recorded so far, for use with C<incomplete_walks>. Returns 0 when the
instance keeps no record.

=cut

sub walk_mark {
  my $snmp = shift;
  return 0 unless $snmp->can('walk_failures');
  return scalar @{ $snmp->walk_failures };
}

=head2 incomplete_walks( $snmp, $mark )

Returns the incomplete walk outcomes recorded since C<walk_mark> returned
C<$mark>, in order. Returns an empty list when the instance keeps no record.

=cut

sub incomplete_walks {
  my ($snmp, $mark) = @_;
  return () unless $snmp->can('walk_failures');
  my $failures = $snmp->walk_failures;
  return @{$failures}[ $mark .. $#{$failures} ];
}

=head2 incomplete_walk_message( $device, $what, @outcomes )

Returns a log message for C<$what> on C<$device> naming each incomplete
walk outcome: its method, table, reason, rows read and walk method, with
the repeaters and SNMP context when there are any.

=cut

sub incomplete_walk_message {
  my ($device, $what, @outcomes) = @_;
  my @walks = map {
    sprintf('%s (%s) %s after %d rows by %s',
      @{$_}{qw/method leaf reason rows walk/})
    . (defined $_->{repeaters} ? " with $_->{repeaters} repeaters" : '')
    . ((defined $_->{context} and length $_->{context})
        ? " in context $_->{context}" : '')
  } @outcomes;
  return sprintf '[%s] %s - kept existing rows, incomplete SNMP walk: %s',
    $device->ip, $what, join '; ', @walks;
}

=head2 incomplete_walks_for( $device, $snmp, $mark, @methods )

Returns the incomplete walk outcomes that could have cut short a table a
worker is about to write: those recorded since C<walk_mark> returned C<$mark>,
then the latest C<walk_status> of each named C<@methods> when it is not
complete, then the job's record of the early C<interfaces> read when
C<interfaces> is among the C<@methods>. Each outcome is returned once.

C<walk_status> is read because a table walked by an earlier worker is cached,
and reading it again records nothing, so the failure lies before C<$mark>. It
holds the latest outcome, so a method that failed and then succeeded on a
re-walk is not returned. An C<absent> reason counts as incomplete although
L<SNMP::Info> marks it complete, because it means the poller could not
translate the object locally, such as a broken MIB checkout.

Returns an empty list when C<enable_incomplete_walk_protection> is false, or
when the instance keeps no walk record.

=cut

sub incomplete_walks_for {
  my ($device, $snmp, $mark, @methods) = @_;
  return () unless setting('enable_incomplete_walk_protection')
    and $snmp->can('walk_failures');

  my @outcomes = incomplete_walks($snmp, $mark);
  if ($snmp->can('walk_status')) {
    foreach my $method (@methods) {
      my $latest = $snmp->walk_status($method);
      push @outcomes, $latest if $latest
        and (not $latest->{complete} or ($latest->{reason} // '') eq 'absent');
    }
  }
  push @outcomes, @{ vars->{'incomplete_walks'}{ $device->ip }{'interfaces'} || [] }
    if grep { $_ eq 'interfaces' } @methods;

  my %seen;
  return grep { not $seen{ refaddr $_ }++ } @outcomes;
}

true;
