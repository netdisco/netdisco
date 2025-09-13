package App::Netdisco::Environment;

use strict;
use warnings;

use File::ShareDir 'dist_dir';
use Path::Class;
use FindBin;

BEGIN {
  if (not ($ENV{DANCER_APPDIR} || '')
      or not -f file($ENV{DANCER_APPDIR}, 'config.yml')) {

      FindBin::again();
      my $me = File::Spec->catfile($FindBin::RealBin, $FindBin::RealScript);
      my $uid = (stat($me))[4] || 0;
      my $home = ($ENV{NETDISCO_HOME} || (getpwuid($uid))[7] || $ENV{HOME});
      $ENV{NETDISCO_HOME} ||= $home;

      $ENV{NETDISCO_DO} ||= File::Spec->catfile($FindBin::RealBin, 'netdisco-do');

      my $auto = dir(dist_dir('App-Netdisco'))->absolute;

      $ENV{DANCER_APPDIR}  ||= $auto->stringify;
      $ENV{DANCER_CONFDIR} ||= $auto->stringify;

      my $test_envdir = dir($home, 'environments')->stringify;
      $ENV{DANCER_ENVDIR} ||= (-d $test_envdir
        ? $test_envdir : $auto->subdir('environments')->stringify);

      $ENV{DANCER_ENVIRONMENT} ||= 'deployment';
      $ENV{PLACK_ENV} ||= $ENV{DANCER_ENVIRONMENT};

      $ENV{DANCER_PUBLIC} ||= $auto->subdir('public')->stringify;
      $ENV{DANCER_VIEWS}  ||= $auto->subdir('views')->stringify;
  }

  {
      # Dancer 1 uses the broken YAML.pm module
      # This is a global sledgehammer - could just apply to Dancer::Config
      use YAML;
      use YAML::XS;
      no warnings 'redefine';
      *YAML::LoadFile = sub { goto \&YAML::XS::LoadFile };
  }
}

1;
