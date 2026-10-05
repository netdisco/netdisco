#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catfile updir/;
use FindBin;
use Text::Balanced 'extract_bracketed';

# netdisco-sshcollector logs in to each device with its configured password,
# so ssh keeps its default host key checking, as App::Netdisco::Transport::SSH
# does. This reads the source because the script forks workers and connects to
# devices.

my $script = catfile($FindBin::Bin, updir(), 'bin', 'netdisco-sshcollector');
open my $fh, '<', $script or die "cannot read $script: $!";
my $source = do { local $/; <$fh> };
close $fh;

my @clients;
while ($source =~ /Net::OpenSSH\s*->\s*new\b/g) {
  my $before = substr($source, 0, $-[0]);
  my $line = 1 + ($before =~ tr/\n//);
  my ($args) = extract_bracketed(substr($source, $+[0]), '()');
  push @clients, { line => $line, args => ($args // '') };
}

subtest 'netdisco_sshcollector__source_text__constructs_one_NetOpenSSH_client' => sub {
  is scalar @clients, 1, 'the guard found the client to check';
};

subtest 'netdisco_sshcollector__anywhere_in_the_script__leaves_StrictHostKeyChecking_alone' => sub {
  unlike $source, qr/StrictHostKeyChecking/i,
    'bin/netdisco-sshcollector does not set StrictHostKeyChecking';
};

subtest 'netdisco_sshcollector__NetOpenSSH_client__still_passes_password_and_BatchMode_no' => sub {
  for my $client (@clients) {
    like $client->{args}, qr/\bpassword\s*=>\s*\$host->\{password\}/,
      "Net::OpenSSH->new at line $client->{line} passes the stanza's password";
    like $client->{args}, qr/-o\s*=>\s*"BatchMode=no"/,
      "Net::OpenSSH->new at line $client->{line} sets BatchMode=no";
  }
};

done_testing;
