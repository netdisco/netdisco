package App::Netdisco::Util::Python;

use Dancer qw/:syntax :script/;

use Path::Class;
use File::ShareDir 'dist_dir';
use Alien::poetry;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/py_install py_cmd/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

sub cipactli {
  my $poetry = Alien::poetry->poetry;
  my $cipactli = Path::Class::Dir->new( dist_dir('App-Netdisco') )
    ->subdir('python')->subdir('netdisco')->stringify;

  return ($poetry, '-C', $cipactli);
}

sub py_install {
  return (cipactli(), 'install', '--sync');
}

sub py_cmd {
  return (cipactli(), 'run', @_);
}

true;
