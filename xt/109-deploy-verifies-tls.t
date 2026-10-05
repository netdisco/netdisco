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
    like $client->{args}, qr/\bverify_SSL\s*=>\s*\$verify_SSL\b/,
      "HTTP::Tiny->new at bin/netdisco-deploy line $client->{line} sets verify_SSL => \$verify_SSL";
  }
};

# The same rule as HTTP::Tiny 0.083 and later, and as the HTTP hooks: verify
# unless PERL_HTTP_TINY_SSL_INSECURE_BY_DEFAULT is exactly 1.
my ($rule) = $source =~ /^my \$verify_SSL\s*=\s*(.+?);\s*$/m;
subtest 'netdisco_deploy__verify_SSL__follows_the_insecure_variable' => sub {
  ok defined $rule, 'bin/netdisco-deploy defines my $verify_SSL';
  return unless defined $rule;
  my $verify = sub { local $ENV{PERL_HTTP_TINY_SSL_INSECURE_BY_DEFAULT} = shift; eval $rule };
  ok $verify->(undef), 'verifies when the variable is unset';
  ok !$verify->('1'), 'does not verify when the variable is 1';
  ok $verify->('0'), 'verifies when the variable is 0';
};

done_testing;
