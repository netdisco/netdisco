#!/usr/bin/env perl

# get_credentials is a command template run through a shell, and %HOST% is
# filled from the device's DNS name, which the device's owner does not control.
# A name that is not shaped like a hostname is replaced by the address.
#
# The command below writes a file. Its absence after a run is what proves the
# injected text never reached the shell.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVIRONMENT} = 'testing' }

use Test::More 0.88;
use File::Temp ();
use File::Spec::Functions 'catfile';
use App::Netdisco;
use Dancer qw/setting/;
use App::Netdisco::Util::DeviceAuth 'get_external_credentials';

my $dir = File::Temp->newdir();

{ package Test::FakeDevice;
  sub new { my ($c, %a) = @_; return bless {%a}, $c }
  sub ip  { $_[0]->{ip} }
  sub dns { $_[0]->{dns} }
}

subtest 'getExternalCredentials__an_ordinary_name__is_used' => sub {
  setting('get_credentials' => 'echo community=%HOST%');
  my @got = get_external_credentials(
    Test::FakeDevice->new(ip => '192.0.2.10', dns => 'switch.example.com'), 'read');
  is scalar @got, 1, 'one credential returned';
  is $got[0]->{community}, 'switch.example.com', 'the name reached the command';
};

subtest 'getExternalCredentials__a_name_carrying_shell_syntax__never_reaches_the_shell' => sub {
  my $marker = catfile($dir, 'fired');
  setting('get_credentials' => 'echo community=%HOST%');
  my @got = get_external_credentials(
    Test::FakeDevice->new(ip => '192.0.2.10',
      dns => "x.example.com'; touch '$marker"), 'read');

  ok !-e $marker, 'the injected command did not run';
  is $got[0]->{community}, '192.0.2.10', 'the address was used in place of the name';
};

subtest 'getExternalCredentials__a_name_with_a_metacharacter__falls_back_to_the_address' => sub {
  setting('get_credentials' => 'echo community=%HOST%');
  foreach my $dns ('a b', 'a;b', 'a`b`', 'a$(b)', 'a|b', '-leading', 'trailing-') {
    my @got = get_external_credentials(
      Test::FakeDevice->new(ip => '192.0.2.10', dns => $dns), 'read');
    is $got[0]->{community}, '192.0.2.10', "[$dns] fell back to the address";
  }
};

done_testing;
