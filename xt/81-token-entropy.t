#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use File::Spec::Functions qw(catdir catfile updir);
use File::Find;
use Test::More 0.88;

# PostgreSQL's random() is a general purpose PRNG, not fit for minting a
# secret. random_token() sources bytes from the operating system instead;
# this guard proves the old idiom is gone from the tree and the new one
# is what it claims to be.
#
# SCOPE: matches only the exact legacy idiom, md5(random()::text).
# TastyJobs.pm's bare random() mints no secret and is deliberately not matched.

use App::Netdisco::Util::Token 'random_token';

my $root = catdir($FindBin::Bin, updir());

# Walked in Perl, not grep, so a failed or unrun search can't read as an
# empty, passing result: find() only warns on a subtree it can't descend into.
my @mints;
my @walk_errors;
{
    local $SIG{__WARN__} = sub { push @walk_errors, @_ };
    for my $dir (catdir($root, 'lib'), catdir($root, 'bin')) {
        find(
            {
                wanted => sub {
                    return unless -f $_;
                    open my $fh, '<:raw', $_
                        or die "cannot read $File::Find::name: $!";
                    local $/;
                    my $content = <$fh>;
                    push @mints, $File::Find::name
                        if $content =~ /md5\(\s*random\(\)\s*::\s*text\s*\)/;
                },
                no_chdir => 1,
            },
            $dir
        );
    }
}

is_deeply(\@walk_errors, [],
  'lib_and_bin_trees__file_find_walk__raises_no_warnings');

is_deeply(\@mints, [],
  'source_tree__after_the_fix__mints_no_secret_with_database_random');

isnt(random_token(), random_token(),
  'random_token__called_twice__returns_a_different_value_each_time');

my $iterations = 500;
my @malformed = grep { !/^[0-9a-f]{64}\z/ }
  map { random_token() } (1 .. $iterations);

is_deeply(\@malformed, [],
  'random_token__over_many_calls__is_always_64_lowercase_hex_characters');

my $token_source = do {
    open my $fh, '<', catfile($root, qw/lib App Netdisco Util Token.pm/)
        or die "cannot read Token.pm: $!";
    local $/;
    <$fh>;
};

like($token_source, qr/Crypt::URandom::urandom/,
  'token_helper__source__reads_from_crypt_urandom');

unlike($token_source, qr/\brand\(/,
  'token_helper__source__never_calls_perls_rand');

done_testing;
