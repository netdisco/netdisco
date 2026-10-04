#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;
use File::Temp ();

# A forwarded address is believed only from a peer named in trusted_proxies.
# metrics_allow is driven through the real PSGI app; token_acl needs a user
# row, so it is asserted against source.

my $envdir;
BEGIN {
  # The app refuses to build without a public directory for
  # Plack::Middleware::Static.
  $ENV{DANCER_PUBLIC} ||= catdir($FindBin::Bin, updir(), 'share', 'public');

  # metrics_path is empty in share/config.yml and Web::Metrics registers its
  # route at load time only if it is set, so no setting() call after the app
  # is loaded can bring the route into being. An environment file is layered
  # over config.yml, which is the only hook that runs early enough.
  $envdir = File::Temp->newdir(CLEANUP => 1);
  open my $env, '>', catfile("$envdir", 'testing.yml')
    or die "cannot write the test environment file: $!";
  print $env "metrics_path: '/xt-metrics'\nmetrics_allow:\n  - '192.0.2.5'\n";
  close $env;

  $ENV{DANCER_ENVDIR} = "$envdir";
  $ENV{DANCER_ENVIRONMENT} = 'testing';
}

use Plack::Test;
use Plack::Util;
use HTTP::Request::Common;
use HTTP::Message::PSGI ();

my $psgi = catfile($FindBin::Bin, updir(), 'bin', 'netdisco-web-fg');
my $app  = eval { Plack::Util::load_psgi($psgi) };

# Never skip: a skip would pass silently.
BAIL_OUT("could not load $psgi: $@") unless $app;

# Dancer's keywords are not imported here on purpose: `use Dancer` in this
# file would load config before the environment above reaches it, and before
# App::Netdisco has said where the config lives.
sub setting { return Dancer::Config::setting(@_) }

is setting('metrics_path'), '/xt-metrics',
  'metricsRoute__test_environment_file__is_registered_at_a_path_this_file_owns';

# Plack::Test::MockHTTP presents every request as coming from 127.0.0.1, so
# the forwarded address below is never the peer and the two can never be
# confused for one another.
my $PEER   = '127.0.0.1';
my $SPOOF  = '192.0.2.5';
my $INNER  = '203.0.113.9';
my $CLIENT = '198.51.100.7';
my $PROXY_CHAIN = "$INNER, $SPOOF";

# Every case sets trusted_proxies: the shipped default names loopback, which is
# what Plack::Test presents as the peer.

test_psgi $app, sub {
  my $cb = shift;

  setting('trusted_proxies' => []);

  setting('metrics_allow' => [$SPOOF]);
  is $cb->(GET '/xt-metrics', 'X-Forwarded-For' => $SPOOF)->code, 403,
    'metricsAllow__an_untrusted_peer_sending_a_header__does_not_admit_the_named_address';

  setting('metrics_allow' => [$PEER]);
  is $cb->(GET '/xt-metrics', 'X-Forwarded-For' => $SPOOF)->code, 200,
    'metricsAllow__an_untrusted_peer_sending_a_header__still_admits_the_socket_peer';

  setting('trusted_proxies' => [$PEER]);

  setting('metrics_allow' => [$SPOOF]);
  is $cb->(GET '/xt-metrics', 'X-Forwarded-For' => $PROXY_CHAIN)->code, 200,
    'metricsAllow__a_trusted_peer_and_a_chain__admits_the_client_the_chain_names';

  setting('metrics_allow' => [$PEER]);
  is $cb->(GET '/xt-metrics', 'X-Forwarded-For' => $PROXY_CHAIN)->code, 403,
    'metricsAllow__a_trusted_peer_and_a_chain__does_not_admit_the_proxy_itself';

  setting('metrics_allow' => [$PEER]);
  is $cb->(GET '/xt-metrics')->code, 200,
    'metricsAllow__a_trusted_peer_sending_no_header__falls_back_to_the_socket_peer';
};

# Net::Server gives a UNIX socket client no peer address; Plack::Test always supplies one.
{
  setting('trusted_proxies' => []);
  setting('metrics_allow'   => [$SPOOF]);

  my $env = GET('/xt-metrics', 'X-Forwarded-For' => $SPOOF)->to_psgi;
  delete $env->{REMOTE_ADDR};

  is $app->($env)->[0], 403,
    'metricsAllow__a_request_with_no_peer_address__refuses_rather_than_admitting_the_header';

  setting('trusted_proxies' => ['127.0.0.1', '::1']);
  setting('metrics_allow'   => [$CLIENT]);

  my $socket_env = GET('/xt-metrics', 'X-Forwarded-For' => $CLIENT)->to_psgi;
  delete $socket_env->{REMOTE_ADDR};

  is $app->($socket_env)->[0], 200,
    'metricsAllow__unix_socket_proxy_forwarding_a_listed_client__is_admitted';
}

# PATH_INFO and REQUEST_METHOD are the minimum Dancer::Request needs to build
# itself; nothing here routes.
sub trusted_for {
  my %env = @_;
  Dancer::SharedData->request(Dancer::Request->new(env => {
    PATH_INFO      => '/',
    REQUEST_METHOD => 'GET',
    %env,
  }));
  return App::Netdisco::Util::Web::trusted_client_address();
}

setting('trusted_proxies' => []);

is trusted_for(
    REMOTE_ADDR             => $SPOOF,
    'netdisco.peer_address' => $PEER,
    HTTP_X_FORWARDED_FOR    => $SPOOF,
  ), $PEER,
  'trustedClientAddress__an_untrusted_peer_sending_a_header__is_the_captured_peer';

is trusted_for(
    REMOTE_ADDR             => $PEER,
    'netdisco.peer_address' => $PEER,
  ), $PEER,
  'trustedClientAddress__an_untrusted_peer_and_no_header__is_the_socket_peer';

# A stack without the capturing middleware, Dancer::Test included, never had
# REMOTE_ADDR rewritten, so the key's absence must not be read as a spoof.
is trusted_for(REMOTE_ADDR => $PEER), $PEER,
  'trustedClientAddress__no_captured_peer_at_all__falls_back_to_remote_addr';

is trusted_for(
    REMOTE_ADDR             => $SPOOF,
    'netdisco.peer_address' => undef,
    HTTP_X_FORWARDED_FOR    => $SPOOF,
  ), '127.0.0.1',
  'trustedClientAddress__unix_socket_peer_with_no_trusted_proxies__is_loopback';

setting('trusted_proxies' => [$PEER]);

is trusted_for(
    REMOTE_ADDR             => $SPOOF,
    'netdisco.peer_address' => $PEER,
    HTTP_X_FORWARDED_FOR    => $PROXY_CHAIN,
  ), $SPOOF,
  'trustedClientAddress__a_trusted_peer_and_one_hop__is_the_address_the_last_proxy_added';

is trusted_for(
    REMOTE_ADDR             => $PEER,
    'netdisco.peer_address' => $PEER,
  ), $PEER,
  'trustedClientAddress__a_trusted_peer_sending_no_header__is_the_socket_peer';

is trusted_for(
    REMOTE_ADDR             => $PEER,
    'netdisco.peer_address' => $PEER,
    HTTP_X_FORWARDED_FOR    => '',
  ), $PEER,
  'trustedClientAddress__a_trusted_peer_and_an_empty_header__is_the_socket_peer';

setting('trusted_proxies' => ['127.0.0.1', '::1']);

is trusted_for(
    REMOTE_ADDR             => $SPOOF,
    'netdisco.peer_address' => '::ffff:127.0.0.1',
    HTTP_X_FORWARDED_FOR    => $CLIENT,
  ), $CLIENT,
  'trustedClientAddress__mapped_loopback_peer__is_a_trusted_proxy';

is trusted_for(
    REMOTE_ADDR             => $SPOOF,
    'netdisco.peer_address' => undef,
    HTTP_X_FORWARDED_FOR    => $CLIENT,
  ), $CLIENT,
  'trustedClientAddress__unix_socket_peer__is_a_loopback_proxy';

setting('trusted_proxies' => []);

is trusted_for(
    REMOTE_ADDR             => $SPOOF,
    'netdisco.peer_address' => '::ffff:192.0.2.44',
  ), '192.0.2.44',
  'trustedClientAddress__mapped_ipv4_peer__is_the_ipv4_address';

setting('trusted_proxies' => [$PEER]);

is trusted_for(
    REMOTE_ADDR             => $PEER,
    'netdisco.peer_address' => $PEER,
    HTTP_X_FORWARDED_FOR    => "::ffff:$CLIENT",
  ), $CLIENT,
  'trustedClientAddress__mapped_forwarded_address__is_the_ipv4_address';

setting('trusted_proxies' => [$PEER, $INNER]);

is trusted_for(
    REMOTE_ADDR             => $INNER,
    'netdisco.peer_address' => $PEER,
    HTTP_X_FORWARDED_FOR    => "$CLIENT, $INNER",
  ), $CLIENT,
  'trustedClientAddress__two_trusted_hops__steps_past_the_inner_proxy_to_the_client';

setting('trusted_proxies' => [$PEER, $INNER, $CLIENT]);

is trusted_for(
    REMOTE_ADDR             => $INNER,
    'netdisco.peer_address' => $PEER,
    HTTP_X_FORWARDED_FOR    => "$CLIENT, $INNER",
  ), $CLIENT,
  'trustedClientAddress__a_chain_that_is_trusted_throughout__is_the_leftmost_address';

# The escape for a platform that gives no nameable upstream.
setting('trusted_proxies' => ['group:__ANY__']);

is trusted_for(
    REMOTE_ADDR             => $SPOOF,
    'netdisco.peer_address' => $SPOOF,
    HTTP_X_FORWARDED_FOR    => $CLIENT,
  ), $CLIENT,
  'trustedClientAddress__the_any_group__believes_a_header_from_any_peer';

setting('trusted_proxies' => []);

# Source assertions for what a request-level test cannot reach: the token_acl
# check, and the middleware order, which moving one entry silently undoes.
sub slurp {
  my $path = catfile($FindBin::Bin, updir(), split m{/}, shift);
  open my $fh, '<', $path or BAIL_OUT("cannot read $path: $!");
  local $/; return <$fh>;
}

my $provider = slurp('lib/App/Netdisco/Web/Auth/Provider/DBIC.pm');

# Scoped to the deciding block: other reads of remote_address in this file are legitimate. An unmatched block leaves an empty string, which fails.
my ($decision) = ($provider =~ m/if \(\$user->token_acl\) \{(.*?)^    \}/ms);
$decision = '' if not defined $decision;

like $decision, qr/trusted_client_address\(\)/,
  'tokenAcl__the_client_address_it_matches__comes_from_the_helper';

# Calling the helper is not using its answer: pin the value too.
like $decision, qr/NetAddr::IP::Lite->new\(\$address\)/,
  'tokenAcl__the_helpers_answer__is_what_the_matched_address_is_built_from';

unlike $decision, qr/request->remote_address/,
  'tokenAcl__the_decision__does_not_read_the_rewritten_address';

my $webutil = slurp('lib/App/Netdisco/Util/Web.pm');
my ($helper) = ($webutil =~ m/^sub trusted_client_address \{(.*?)^\}/ms);
$helper = '' if not defined $helper;

unlike $helper, qr/behind_proxy/,
  'trustedClientAddress__the_helper__does_not_consult_behind_proxy';

my $webfg = slurp('bin/netdisco-web-fg');

# Both positions are asserted, not just their order: index() answers -1 for a
# capture that is not in the file at all, which would read as "early enough".
my $capture = index($webfg, q{$env->{'netdisco.peer_address'} = $env->{REMOTE_ADDR}});
my $rewrite = index($webfg, q{'Plack::Middleware::ReverseProxy'});

ok(($capture > 0 and $rewrite > 0 and $capture < $rewrite),
  'middlewareList__the_peer_capture__is_listed_before_the_proxy_rewrite');

done_testing;
