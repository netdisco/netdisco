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
  looks_garbled
  ungarble
  scan_config_encoding
  scan_stored_encoding
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

=head2 looks_garbled( $string )

True when the string holds a character from U+00C2 to U+00F4 followed by one
from U+0080 to U+00BF, which is how UTF-8 octets look when read as Latin-1.

=cut

sub looks_garbled {
  my ($string) = @_;
  return (defined $string and $string =~ m/[\x{C2}-\x{F4}][\x{80}-\x{BF}]/) ? 1 : 0;
}

=head2 ungarble( $string, \@charsets )

Returns the text that C<$string> would have been had its characters been read
as octets, using C<decode_text_with>. Returns undef when the string holds a
character which Latin-1 cannot encode, so it cannot be garbled in that way.

=cut

sub ungarble {
  my ($string, $charsets) = @_;
  my $bytes = try { Encode::encode('iso-8859-1', $string, $CHECK) };
  return undef unless defined $bytes;
  return scalar decode_text_with($bytes, $charsets || []);
}

=head2 scan_config_encoding( $config )

Walks hashes (keys and values) and arrays in C<$config> and returns a list of
C<< { path => 'discover_no[2]', value => ..., suggestion => ... } >> for every
string which C<looks_garbled>. Other references are skipped. Reads only the
data it is given.

=cut

sub scan_config_encoding {
  my ($config) = @_;
  my @findings;
  _walk_config($config, '', \@findings);
  return @findings;
}

sub _walk_config {
  my ($node, $path, $findings) = @_;
  my $type = ref $node;

  if (!$type) {
    return unless looks_garbled($node);
    push @$findings, { path => $path, value => $node,
                       suggestion => ungarble($node, []) };
  }
  elsif ($type eq 'ARRAY') {
    _walk_config($node->[$_], "$path\[$_]", $findings) for 0 .. $#$node;
  }
  elsif ($type eq 'HASH') {
    foreach my $key (sort keys %$node) {
      my $child = length $path ? "$path.$key" : $key;
      _walk_config($key, "$child (key)", $findings) if looks_garbled($key);
      _walk_config($node->{$key}, $child, $findings);
    }
  }
}

=head2 scan_stored_encoding( $schema, $limit )

Reads the database only. Returns findings for stored text that looks garbled
or holds U+FFFD, in C<device.name>, C<description>, C<vendor>, C<os> and
C<os_ver>, C<device_port.descr>, C<device_vlan.description> and
C<device_port_ssid.ssid>. Each finding is C<< { ip, column, value, suggestion } >>
where C<suggestion> is undef for U+FFFD, whose original octets are not
recoverable. At most C<$limit> findings are returned per column, followed by
C<< { column, more => $count } >> for the rest.

=cut

my @STORED_COLUMNS = (
  [Device => 'device', 'name'], [Device => 'device', 'description'],
  [Device => 'device', 'vendor'], [Device => 'device', 'os'],
  [Device => 'device', 'os_ver'], [DevicePort => 'device_port', 'descr'],
  [DeviceVlan => 'device_vlan', 'description'],
  [DevicePortSsid => 'device_port_ssid', 'ssid'],
);

sub scan_stored_encoding {
  my ($schema, $limit) = @_;
  # PostgreSQL regex escapes, so no non-ASCII bind value depends on DBD::Pg
  my $pattern = '[Â-ô][\u0080-¿]|�';
  my (@findings, %charsets);

  foreach my $spec (@STORED_COLUMNS) {
    my ($source, $table, $column) = @$spec;
    my $rs = $schema->resultset($source)->search(
      { $column => { '~' => $pattern } },
      { columns => ['ip', $column], order_by => ['ip', $column] });
    my $total = $rs->count;

    foreach my $row ($rs->search(undef, { rows => $limit })->all) {
      my $value = $row->get_column($column);
      my $ip = $row->get_column('ip');
      $charsets{$ip} ||= do {
        my $device = $schema->resultset('Device')->find($ip);
        snmp_charsets_for($device);
      };
      push @findings, { ip => $ip, column => "$table.$column", value => $value,
        suggestion => (looks_garbled($value) ? ungarble($value, $charsets{$ip}) : undef) };
    }
    push @findings, { column => "$table.$column", more => $total - $limit }
      if $total > $limit;
  }
  return @findings;
}

1;
