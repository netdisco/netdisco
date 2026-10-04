#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catfile updir/;
use FindBin;
use Text::Balanced 'extract_bracketed';

# netdisco-deploy runs what it downloads, and HTTP::Tiny before 0.083 does
# not verify unless asked, so every client must ask. This reads the source
# because the script prompts and reaches the network.

my $script = catfile($FindBin::Bin, updir(), 'bin', 'netdisco-deploy');
open my $fh, '<', $script or die "cannot read $script: $!";
my $source = do { local $/; <$fh> };
close $fh;

my @clients;
while ($source =~ /HTTP::Tiny\s*->\s*new\b/g) {
  my $before = substr($source, 0, $-[0]);
  my $line = 1 + ($before =~ tr/\n//);
  my ($args) = extract_bracketed(substr($source, $+[0]), '()');
  push @clients, { line => $line, args => ($args // '') };
}

subtest 'netdisco_deploy__source_text__constructs_at_least_one_HTTP_Tiny_client' => sub {
  cmp_ok scalar @clients, '>=', 1, 'the guard found a client to check';
};

subtest 'netdisco_deploy__every_HTTP_Tiny_client__sets_verify_SSL' => sub {
  for my $client (@clients) {
    like $client->{args}, qr/\bverify_SSL\s*=>\s*1\b/,
      "HTTP::Tiny->new at bin/netdisco-deploy line $client->{line} sets verify_SSL => 1";
  }
};

done_testing;
