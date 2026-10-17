package App::Netdisco::Util::SNMPText;

# DBD::Pg 3.3+ reads undecoded strings as Latin-1 under pg_enable_utf8, so SNMP text is decoded here first

use Dancer qw/:syntax :script/;

use App::Netdisco::Util::Permission 'acl_matches';

use Encode ();
use Try::Tiny;
use Scalar::Util 'blessed';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  decode_text_with
  decode_snmp_text
  decode_snmp_data
  decode_cli_extra
  snmp_charsets_for
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

my %warned;
my $CHECK = Encode::FB_CROAK | Encode::LEAVE_SRC;

=head1 NAME

App::Netdisco::Util::SNMPText

=head1 DESCRIPTION

Helper functions to turn the octets of an SNMP text value into a character
string, without double encoding and without substituting U+FFFD.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 snmp_charsets_for( $device )

Returns an array reference of fallback charset names configured for the
device, most specific ACL keys first and C<group:__ANY__> last, without
duplicates. The C<snmp_charset> setting is a list of maps from ACL to charsets.

=cut

sub snmp_charsets_for {
  my ($device) = @_;
  return [] unless $device;

  my (@charsets, %seen);
  foreach my $map (@{ setting('snmp_charset') || [] }) {
    my @keys = ((sort { $a cmp $b } grep { $_ ne q{group:__ANY__} } keys %$map),
                (exists $map->{'group:__ANY__'} ? 'group:__ANY__' : ()));
    foreach my $key (@keys) {
      next unless acl_matches($device, $key);
      push @charsets, grep { not $seen{$_}++ } @{ $map->{$key} };
    }
  }
  return \@charsets;
}

=head2 decode_text_with( $bytes, \@charsets )

Returns the character string for C<$bytes>. Undef and empty values are
returned unchanged, as is a string which already holds characters above 0xFF.

Plain ASCII is returned as is. Otherwise valid UTF-8 is tried first, then each
charset in the list (accepted only if encoding the result gives back exactly
C<$bytes> and it holds no private use or U+FFFD characters), and lastly Latin-1, which accepts any octets. A charset name which
L<Encode> does not know is skipped, with one warning per process.

In list context returns C<($text, $how)> where C<$how> is C<ascii>, C<UTF-8>,
the charset name, or C<latin1>.

=cut

sub decode_text_with {
  my ($bytes, $charsets) = @_;
  return (wantarray ? ($bytes, 'ascii') : $bytes)
    if !defined $bytes or $bytes eq '';

  my ($text, $how) = _decode_octets($bytes, $charsets || []);
  return wantarray ? ($text, $how) : $text;
}

sub _decode_octets {
  my ($bytes, $charsets) = @_;

  return ($bytes, 'UTF-8')
    if utf8::is_utf8($bytes) and $bytes =~ m/[^\x00-\xFF]/;
  return ($bytes, 'ascii') if $bytes !~ m/[^\x00-\x7F]/;

  my $utf8 = try { Encode::decode('UTF-8', $bytes, $CHECK) };
  return ($utf8, 'UTF-8') if defined $utf8;

  # a code ref defers the per-device ACL walk until a fallback is needed
  $charsets = $charsets->() if ref $charsets eq ref sub {};
  foreach my $charset (@$charsets) {
    my $text = _decode_round_trip($bytes, $charset);
    return ($text, $charset) if defined $text;
  }

  return (Encode::decode('iso-8859-1', $bytes), 'latin1');
}

# A multi-byte charset can accept octets it does not mean, so only a result
# which encodes back to the same octets is trusted. Encode 3.21 also maps a
# lone 0xFF in GBK to private use U+F8F5, which round-trips, so those and
# U+FFFD are rejected too.
sub _decode_round_trip {
  my ($bytes, $charset) = @_;

  if (not Encode::find_encoding($charset)) {
    warning sprintf 'snmp_charset: unknown charset [%s], ignored', $charset
      unless $warned{$charset}++;
    return undef;
  }

  return try {
    my $text = Encode::decode($charset, $bytes, $CHECK);
    ($text !~ m/[\p{Co}\x{FFFD}]/
      and Encode::encode($charset, $text, $CHECK) eq $bytes) ? $text : undef;
  } catch { undef };
}

=head2 decode_snmp_text( $bytes, $device_or_undef, $field_label )

Decodes as C<decode_text_with> does, using the charsets from
C<snmp_charsets_for> for the device, or none when the device is undef. The
charsets are looked up only when the value is neither ASCII nor UTF-8. Returns
the text. When the value is neither UTF-8 nor in a configured charset, it is
stored as Latin-1 and a debug message names the device, C<$field_label> and the
octets.

=cut

sub decode_snmp_text {
  my ($bytes, $device, $field_label) = @_;
  return $bytes if !defined $bytes or $bytes eq '';

  my ($text, $how) = _decode_octets($bytes,
    sub { $device ? snmp_charsets_for($device) : [] });
  debug sprintf ' [%s] %s bytes %s are not UTF-8 or a configured snmp_charset; stored as Latin-1',
    ($device ? $device->ip : '-'), $field_label, unpack('H*', $bytes)
    if $how eq 'latin1';

  return $text;
}

=head2 decode_snmp_data( $data, $device_or_undef, $field_label )

Returns a copy of C<$data> in which every defined plain scalar, in hashes and
arrays to any depth, has been through C<decode_snmp_text>. Hash keys are left
as they are, and blessed objects and code references pass through unchanged.
C<$field_label> defaults to C<data>. The argument is never modified.

=cut

sub decode_snmp_data {
  my ($data, $device, $field_label) = @_;
  $field_label = 'data' unless defined $field_label;

  return $data if blessed $data;
  my $type = ref $data;
  return [ map { decode_snmp_data($_, $device, $field_label) } @$data ]
    if $type eq 'ARRAY';
  return { map { $_ => decode_snmp_data($data->{$_}, $device, $field_label) } keys %$data }
    if $type eq 'HASH';
  return $data if $type;

  return decode_snmp_text($data, $device, $field_label);
}

=head2 decode_cli_extra( $extra )

Decodes the C<-e> text given to C<netdisco-do> for a C<cf_> action, which
arrives as raw octets, with no device charsets. Undef and empty values are
returned unchanged.

=cut

sub decode_cli_extra {
  my ($extra) = @_;
  return decode_text_with($extra, []);
}

1;
