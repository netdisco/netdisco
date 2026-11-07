#!/usr/bin/env perl

# Authen::TacacsPlus 0.28 does not compile under GCC 15 (#1807, #1377), so
# Netdisco no longer installs it. These check that a site without it loses
# nothing but TACACS+ logins, and that a site using TACACS+ is told what to
# install. The module is hidden with an @INC hook, then replaced by a stand-in
# that records what it is given.

use strict;
use warnings;

our ($hide_tacacs, $broken_tacacs);

# "broken" stands for a copy built against an older perl or libc, which an OS
# upgrade leaves behind: found, but dies while loading
BEGIN {
  $ENV{DANCER_ENVDIR} = '/dev/null';
  $hide_tacacs = 1;
  unshift @INC, sub {
    return unless $_[1] eq 'Authen/TacacsPlus.pm';
    if ($broken_tacacs) {
      my $source = qq{die "TacacsPlus.so: undefined symbol: Perl_xs_handshake\\n";\n};
      open my $fh, '<', \$source or die $!;
      return $fh;
    }
    die "Can't locate Authen/TacacsPlus.pm in \@INC (hidden by this test)\n" if $hide_tacacs;
    return;
  };
}

use Test::More 0.88;
use App::Netdisco;
use Dancer qw/:syntax !pass/;
use Dancer::Logger::Capture ();
use App::Netdisco::Util::Web qw/tacacs_configured tacacs_unavailable tacacs_startup_warning/;

config->{logger} = 'capture';
config->{log} = 'debug';
Dancer::Logger->init(config->{logger}, config);

sub logged_at {
  my $level = shift;
  return grep { $_->{level} eq $level } @{ Dancer::Logger::Capture->trap->read };
}

my $servers = [ Host => '192.0.2.1', Key => 'k', Port => 'tacacs', Timeout => 15 ];

subtest 'tacacsUnavailable__module_hidden__returns_install_advice' => sub {
  my $why = tacacs_unavailable();
  like($why, qr/^Authen::TacacsPlus is not installed\./, 'names the module');
  like($why, qr{~/bin/localenv cpanm --notest Authen::TacacsPlus}, 'gives the install command');
  like($why, qr{CFLAGS="-std=gnu17"}, 'gives the GCC 15 form');
};

subtest 'tacacsUnavailable__called_twice__returns_advice_both_times' => sub {
  ok(tacacs_unavailable(), 'first call');
  ok(tacacs_unavailable(), 'second call, after perl cached the failed require');
};

subtest 'tacacsConfigured__shipped_default_hash__is_false' => sub {
  set tacacs => {};
  ok(!tacacs_configured(), 'the default {} is not a configuration');
  set tacacs => [];
  ok(!tacacs_configured(), 'an empty list is not a configuration');
  set tacacs => $servers;
  ok(tacacs_configured(), 'a server list is');
};

subtest 'tacacsStartupWarning__not_configured_module_hidden__returns_nothing' => sub {
  for my $unset ({}, []) {
    set tacacs => $unset;
    is(tacacs_startup_warning(), undef, 'a site without TACACS+ is not warned');
  }
};

subtest 'tacacsStartupWarning__configured_module_hidden__names_the_problem' => sub {
  set tacacs => $servers;
  like(tacacs_startup_warning(), qr/^TACACS\+ is configured, but Authen::TacacsPlus is not installed\./,
    'the warning says what is missing');
};

subtest 'providerLoad__module_hidden__loads' => sub {
  ok(eval { require App::Netdisco::Web::Auth::Provider::DBIC; 1 }, 'the auth provider loads')
    or diag $@;
};

my $provider = 'App::Netdisco::Web::Auth::Provider::DBIC';

subtest 'matchWithTacacs__not_configured_module_hidden__returns_false_quietly' => sub {
  for my $unset ({}, []) {
    set tacacs => $unset;
    Dancer::Logger::Capture->trap->read;
    ok(!$provider->match_with_tacacs('pw', 'alice'), 'refused');
    is(scalar(logged_at('error')), 0, 'nothing logged');
  }
};

subtest 'matchWithTacacs__module_hidden__refuses_and_logs_advice_each_time' => sub {
  set tacacs => $servers;
  for my $attempt (1, 2) {
    Dancer::Logger::Capture->trap->read;
    ok(!$provider->match_with_tacacs('pw', 'alice'), "attempt $attempt refused");
    ok((grep { $_->{message} =~ /TACACS\+ login for alice refused: Authen::TacacsPlus is not installed/ }
          logged_at('error')),
      "attempt $attempt logs the advice");
  }
};

subtest 'webStartup__tacacs_configured_module_hidden__logs_warning' => sub {
  set tacacs => $servers;
  Dancer::Logger::Capture->trap->read;
  require App::Netdisco::Web;
  ok((grep { $_->{message} =~ /TACACS\+ is configured, but Authen::TacacsPlus is not installed/ }
        logged_at('warning')),
    'the startup warning names the problem');
};

subtest 'tacacsUnavailable__installed_but_broken__says_so_and_advises_reinstall' => sub {
  local $broken_tacacs = 1;
  delete $INC{'Authen/TacacsPlus.pm'};
  my $first = tacacs_unavailable();
  like($first, qr/^Authen::TacacsPlus is installed but cannot be loaded/, 'does not claim it is missing');
  like($first, qr/undefined symbol: Perl_xs_handshake/, 'carries the load error');
  like($first, qr{~/bin/localenv cpanm --notest --reinstall Authen::TacacsPlus}, 'advises a rebuild');
  like($first, qr{CFLAGS="-std=gnu17" ~/bin/localenv cpanm --notest --reinstall Authen::TacacsPlus},
    'gives the GCC 15 form of the rebuild');
  like(tacacs_unavailable(), qr/^Authen::TacacsPlus is installed but cannot be loaded/,
    'a retry, which perl answers with "Attempt to reload", still says so');
};

# the stand-in replaces the real module from here on
$hide_tacacs = 0;
delete $INC{'Authen/TacacsPlus.pm'};
{
  package Authen::TacacsPlus;
  our (@new_args, $fail_new);
  sub new { my $class = shift; @new_args = @_; return $fail_new ? undef : bless {}, $class }
  sub authen { my ($self, $user, $pass) = @_; return ($user eq 'alice' and $pass eq 'right') ? 1 : 0 }
  sub close { 1 }
  sub errmsg { 'stub error' }
}
$INC{'Authen/TacacsPlus.pm'} = __FILE__;

subtest 'matchWithTacacs__stub_module__passes_servers_and_returns_result' => sub {
  set tacacs => $servers;
  ok($provider->match_with_tacacs('right', 'alice'), 'right password accepted');
  is_deeply(\@Authen::TacacsPlus::new_args, $servers, 'the configured servers reach new() unchanged');
  ok(!$provider->match_with_tacacs('wrong', 'alice'), 'wrong password refused');
};

subtest 'matchWithTacacs__server_unreachable__refuses' => sub {
  set tacacs => $servers;
  local $Authen::TacacsPlus::fail_new = 1;
  ok(!$provider->match_with_tacacs('right', 'alice'), 'refused when new() fails');
};

done_testing;
