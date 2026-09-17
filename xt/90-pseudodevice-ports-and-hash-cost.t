#!/usr/bin/env perl

# Two unrelated hardenings that share a test file because neither needs more
# than a few lines.
#
# The pseudo device port count becomes a range which is materialized into a
# list, so it is bounded rather than taken from the request.
#
# The passphrase plugin falls back to a bcrypt cost of 4 when the config names
# none, so share/config.yml now names one. A hash carries the cost it was made
# with, which is why raising it needs no migration and why the old hash below
# still verifies.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVIRONMENT} = 'testing' }

use Test::More 0.88;
use App::Netdisco;
use Dancer::Plugin::Passphrase;
use App::Netdisco::Web::Plugin::AdminTask::PseudoDevice;

my $ports_ok = \&App::Netdisco::Web::Plugin::AdminTask::PseudoDevice::ports_count_ok;

subtest 'portsCountOk__a_plausible_chassis__is_accepted' => sub {
  ok $ports_ok->($_), "$_ ports accepted" for qw/1 48 512 7300 9999/;
};

subtest 'portsCountOk__more_than_any_real_device__is_refused' => sub {
  ok !$ports_ok->($_), "$_ ports refused" for qw/10000 999999 99999999/;
};

subtest 'portsCountOk__not_a_count__is_refused' => sub {
  ok !$ports_ok->($_), 'refused' for (0, '', 'x', '-1', '1e9', '5.5');
  ok !$ports_ok->(undef), 'undef is refused';
};

subtest 'passphrase__a_newly_minted_hash__uses_a_modern_work_factor' => sub {
  my $hash = passphrase('correct horse battery staple')->generate->rfc2307;
  like $hash, qr/^\{CRYPT\}\$2a\$(\d\d)\$/, 'a bcrypt hash is minted';
  my ($cost) = $hash =~ m/^\{CRYPT\}\$2a\$(\d\d)\$/;
  cmp_ok $cost, '>=', 12, "work factor is $cost";
};

subtest 'passphrase__a_hash_minted_at_the_old_cost__still_matches' => sub {
  # made with cost 4, the fallback this config replaces
  my $old = '{CRYPT}$2a$04$5KwmUrX7uVDh19l9H38C5OUn4L/lLTVyc/oWOPlMbDogiICkdhq4q';
  ok passphrase('x')->matches($old), 'an existing password still logs in';
  ok !passphrase('y')->matches($old), 'and a wrong one still does not';
};

done_testing;
