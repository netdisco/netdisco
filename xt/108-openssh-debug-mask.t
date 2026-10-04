#!/usr/bin/env perl

# Neither SSH entry point may set Net::OpenSSH debug bit 512.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };
use File::Spec::Functions qw/catfile updir/;
use FindBin;

use App::Netdisco;
use App::Netdisco::Transport::SSH;
use Dancer qw/:script !pass/;

my $script = catfile( $FindBin::Bin, updir(), 'bin', 'netdisco-sshcollector' );

open my $fh, '<', $script or die "cannot read $script: $!";
my $source = do { local $/; <$fh> };
close $fh;

my @assignments = ( $source =~ m/^\s*\$Net::OpenSSH::debug\s*=\s*([^;]+);/mg );

subtest 'netdiscoSshcollector__opensshdebug_option__sets_one_debug_mask' => sub {
  is scalar @assignments, 1, 'exactly one assignment to $Net::OpenSSH::debug';
  like $assignments[0], qr/\A[0-9|\s]+\z/, 'the mask is a literal of numeric flags';
};

subtest 'netdiscoSshcollector__opensshdebug_option__leaves_os_tracing_off' => sub {
  my $mask = ( $assignments[0] // '' ) =~ m/\A[0-9|\s]+\z/
    ? eval $assignments[0] : ~0;
  ok $mask, 'the mask enables debugging';
  is $mask & 512, 0, 'bit 512 is clear';
};

{
  package FakeDevice;
  sub ip { '192.0.2.1' }

  package FakeSSH;
  sub error { undef }
}

config->{'device_auth'} = [{
  platform => 'IOS', username => 'netdisco', password => 'netdisco',
}];

sub debug_mask_at_connect {
  my $captured;
  local *App::Netdisco::Transport::SSH::get_device = sub { bless {}, 'FakeDevice' };
  local *Net::OpenSSH::new = sub { $captured = $Net::OpenSSH::debug; bless {}, 'FakeSSH' };
  App::Netdisco::Transport::SSH->instance->sessions( {} );
  App::Netdisco::Transport::SSH->session_for('192.0.2.1');
  return $captured;
}

subtest 'TransportSSH_session_for__ssh_trace_all_flags__leaves_os_tracing_off' => sub {
  local $ENV{SSH_TRACE} = -1;
  my $mask = debug_mask_at_connect();
  is $mask & 512, 0, 'bit 512 is clear';
  is $mask & 255, 255, 'every other documented flag is kept';
};

subtest 'TransportSSH_session_for__ssh_trace_without_512__passes_mask_through' => sub {
  local $ENV{SSH_TRACE} = 4|8;
  is debug_mask_at_connect(), 12, 'the mask is unchanged';
};

subtest 'TransportSSH_session_for__ssh_trace_unset__leaves_debugging_off' => sub {
  delete local $ENV{SSH_TRACE};
  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, @_ };
  ok !debug_mask_at_connect(), 'debugging is off';
  is_deeply \@warnings, [], 'no warnings';
};

done_testing;
