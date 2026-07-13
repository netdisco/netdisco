package App::Netdisco::Util::Configuration;

use Dancer qw/:syntax :script/;

use Hash::Merge::Simple;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  merge_into_configuration
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

sub merge_into_configuration {
    my $newconfig = shift;
    return unless ref $newconfig eq ref {};
    my $SETTINGS = config();
    $SETTINGS = Hash::Merge::Simple::merge( $SETTINGS, $newconfig );
    set($_ => $SETTINGS->{$_}) for keys %$newconfig;
}

true;