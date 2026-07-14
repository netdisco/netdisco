package App::Netdisco::Util::Configuration;

use Dancer qw/:syntax :script/;

use Hash::Merge::Simple;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  merge_into_configuration
  parse_config_string_to_dict
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

sub merge_into_configuration {
    my $newconfig = shift;
    $newconfig =
      parse_config_string_to_dict($newconfig) if ref $newconfig eq q{};
    return unless ref $newconfig eq ref {};
    my $SETTINGS = config();
    $SETTINGS = Hash::Merge::Simple::merge( $SETTINGS, $newconfig );
    set($_ => $SETTINGS->{$_}) for keys %$newconfig;
}

sub parse_config_string_to_dict {
  my $extra = shift;
  return {} unless $extra;

  # either a device_auth tag hint, or
  # some other use of subaction (file ref, log comment, etc)
  return {device_auth_tag_hint => $extra} if $extra !~ m/=/;

  # must be key1=val1,key2=val2
  my $dict = {};
  my @kvs = split m/,/, $extra;
  foreach my $kv (@kvs) {
      next unless $kv;
      die "bad syntax for subaction, missing =\n" unless $kv =~ m/=/;
      my ($k, $v) = split m/=/, $kv, 2;
      $dict->{$k} = $v;
  }

  return $dict;
}

true;