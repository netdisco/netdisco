#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;
use File::Temp ();

# The route carries two independent optional controls, and this file tests the
# whole matrix rather than either one alone.
#
#   metrics_allow  an address list. Empty, which is the shipped default, means
#                  any: the setting is optional, so configuring neither control
#                  publishes the endpoint.
#   metrics_token  a bearer token.
#
# Both set is an AND, and the address check runs first, so an address outside
# the list is refused whatever token it carries. That ordering is the reason a
# token cannot be used to reach the endpoint from elsewhere.
#
# The endpoint answers with or without a database, and AuthN exempts
# metrics_path from login, so nothing here needs a user.

my $envdir;
BEGIN {
  # As xt/43 and xt/82: the app refuses to build without a public directory.
  $ENV{DANCER_PUBLIC} ||= catdir($FindBin::Bin, updir(), 'share', 'public');

  # The route registers at load time only if metrics_path is set, so it has to
  # come from an environment file layered over config.yml rather than from a
  # setting() call after the app is built.
  $envdir = File::Temp->newdir(CLEANUP => 1);
  open my $env, '>', catfile("$envdir", 'testing.yml')
    or die "cannot write the test environment file: $!";
  print $env "metrics_path: '/xt-metrics'\n";
  close $env;

  $ENV{DANCER_ENVDIR} = "$envdir";
  $ENV{DANCER_ENVIRONMENT} = 'testing';
}

use Plack::Test;
use Plack::Util;
use HTTP::Request::Common;

my $psgi = catfile($FindBin::Bin, updir(), 'bin', 'netdisco-web-fg');
my $app  = eval { Plack::Util::load_psgi($psgi) };
BAIL_OUT("could not load $psgi: $@") unless $app;

# Dancer's keywords are not imported here on purpose, as in xt/82: `use Dancer`
# would load config before the environment above reaches it, and its `pass`
# collides with Test::More's.
sub setting { return Dancer::Config::setting(@_) }

is setting('metrics_path'), '/xt-metrics',
  'metricsRoute__test_environment_file__is_registered_at_a_path_this_file_owns';

test_psgi $app, sub {
  my $cb = shift;

  # The shipped default, which is what a site that set only metrics_path has.
  setting('metrics_allow' => []);
  setting('metrics_token' => '');

  is $cb->(GET '/xt-metrics')->code, 200,
    'metricsAllow__the_shipped_empty_list__publishes_rather_than_refusing_everyone';

  # A token alone could never be reached before, because the empty list
  # refused the request first.
  setting('metrics_allow' => []);
  setting('metrics_token' => 'a-secret');

  is $cb->(GET '/xt-metrics')->code, 401,
    'metricsToken__a_token_with_no_allow_list__is_reached_rather_than_shadowed';

  is $cb->(GET '/xt-metrics',
      'Authorization' => 'Bearer a-secret')->code, 200,
    'metricsToken__a_token_with_no_allow_list__admits_the_bearer';

  setting('metrics_allow' => ['192.0.2.5']);
  setting('metrics_token' => '');

  is $cb->(GET '/xt-metrics')->code, 403,
    'metricsAllow__a_configured_list_that_excludes_the_caller__refuses';

  setting('metrics_allow' => ['127.0.0.1']);

  is $cb->(GET '/xt-metrics')->code, 200,
    'metricsAllow__a_configured_list_that_includes_the_caller__admits';

  # Both controls set: the address check runs first, so a correct token does
  # not reach past a list the caller is not on.
  setting('metrics_allow' => ['192.0.2.5']);
  setting('metrics_token' => 'a-secret');

  is $cb->(GET '/xt-metrics',
      'Authorization' => 'Bearer a-secret')->code, 403,
    'metricsControls__an_excluded_address_with_a_correct_token__is_still_refused';

  setting('metrics_allow' => ['127.0.0.1']);

  is $cb->(GET '/xt-metrics')->code, 401,
    'metricsControls__an_included_address_with_no_token__is_refused_by_the_token';

  is $cb->(GET '/xt-metrics',
      'Authorization' => 'Bearer a-secret')->code, 200,
    'metricsControls__an_included_address_and_a_correct_token__admits';
};

done_testing;
