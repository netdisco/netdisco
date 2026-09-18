#!/usr/bin/env perl

# A bcrypt hash carries the work factor it was made with, so raising the
# configured one reaches an existing password only when that password is
# rewritten. The only moment the plaintext is available is a successful login.
#
# The user row here is a fake that records what it was asked to update, so a
# rewrite is proven by the call rather than by reading a database.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVIRONMENT} = 'testing' }

use Test::More 0.88;
use App::Netdisco;
use Dancer qw/setting/;
use Dancer::Plugin::Passphrase;
use App::Netdisco::Web::Auth::Provider::DBIC;

{ package Test::FakeRealm;
  sub new { bless {}, shift }
  sub realm_settings { return {} }
}
{ package Test::FakeUser;
  sub new { my ($c, %a) = @_; return bless { %a, updates => [] }, $c }
  sub password { $_[0]->{password} }
  sub update {
      my ($self, $data) = @_;
      push @{ $self->{updates} }, $data;
      $self->{password} = $data->{password};
      return $self;
  }
}

my $match    = \&App::Netdisco::Web::Auth::Provider::DBIC::match_with_local_pass;
my $is_stale = \&App::Netdisco::Web::Auth::Provider::DBIC::password_hash_is_stale;
my $PASSWORD = 'correct horse battery staple';

sub cost_of { my ($c) = (shift || '') =~ m/^\{CRYPT\}\$2a\$(\d\d)\$/; return $c }
sub hash_at { return passphrase($PASSWORD)->generate({ cost => shift })->rfc2307 }

subtest 'passwordHashIsStale__a_bcrypt_hash_below_the_configured_factor__is_stale' => sub {
  ok $is_stale->('{CRYPT}$2a$04$abcdefghijklmnopqrstuv'), 'cost 4 is stale';
  ok !$is_stale->('{CRYPT}$2a$12$abcdefghijklmnopqrstuv'), 'the configured cost is not';
  ok !$is_stale->('{CRYPT}$2a$13$abcdefghijklmnopqrstuv'),
    'a higher cost is not stale, so a hash is never downgraded';
};

subtest 'passwordHashIsStale__anything_not_bcrypt__is_left_alone' => sub {
  ok !$is_stale->($_), 'left alone' for
    ('{SSHA}deadbeef', '5f4dcc3b5aa765d61d8327deb882cf99', '', '{CRYPT}$2y$04$x');
  ok !$is_stale->(undef), 'undef is left alone';
};

subtest 'matchWithLocalPass__a_good_login_on_a_stale_hash__rewrites_it' => sub {
  my $user = Test::FakeUser->new(password => hash_at(4));
  is $match->(Test::FakeRealm->new, $PASSWORD, $user), 1, 'the login succeeds';
  is scalar @{ $user->{updates} }, 1, 'the row is updated once';
  is cost_of($user->password), '12', 'and now carries the configured factor';
  ok passphrase($PASSWORD)->matches($user->password),
    'the rewritten hash still verifies the same password';
};

subtest 'matchWithLocalPass__a_failed_login__rewrites_nothing' => sub {
  my $user = Test::FakeUser->new(password => hash_at(4));
  is $match->(Test::FakeRealm->new, 'not the password', $user), 0, 'the login fails';
  is scalar @{ $user->{updates} }, 0, 'nothing is written';
  is cost_of($user->password), '04', 'the stored hash is untouched';
};

subtest 'matchWithLocalPass__a_hash_already_at_the_configured_factor__is_not_rewritten' => sub {
  my $user = Test::FakeUser->new(password => hash_at(12));
  is $match->(Test::FakeRealm->new, $PASSWORD, $user), 1, 'the login succeeds';
  is scalar @{ $user->{updates} }, 0, 'no needless write on every login';
};

subtest 'matchWithLocalPass__safe_password_store_off__rewrites_nothing' => sub {
  my $was = setting('safe_password_store');
  setting('safe_password_store' => 0);
  my $user = Test::FakeUser->new(password => hash_at(4));
  is $match->(Test::FakeRealm->new, $PASSWORD, $user), 1, 'the login still succeeds';
  is scalar @{ $user->{updates} }, 0, 'the existing opt-out is honored';
  setting('safe_password_store' => $was);
};

done_testing;
