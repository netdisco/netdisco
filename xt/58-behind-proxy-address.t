#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;

# The testing environment, as xt/57 uses it: it supplies session_cookie_key,
# without which loading the web app dies before the first assertion.
BEGIN { $ENV{DANCER_ENVIRONMENT} = 'testing'; }

# With behind_proxy set, Dancer answers request->address with the
# X-Forwarded-For header exactly as it arrived. One proxy puts one address in
# that header and everything works, which is why this survived; two proxies put
# a comma separated chain there, and a chain is not an address:
#
#   NetAddr::IP::Lite->new('203.0.113.5, 198.51.100.1') is undef, so
#   acl_matches_only() rejects, and every API token carrying a token_acl gets
#   401 with nothing in the log naming the cause.
#
#   user_log.userip is an inet column (schema_versions 1-2), so the three
#   login and logout inserts in AuthN.pm fail on the chain as well.
#
# Web.pm overrides address() to take the LAST element, which is the one the
# trusted proxy appended and the one Plack::Middleware::ReverseProxy picks with
# its own /([^,\s]+)$/. Addresses to the left of it are client supplied and can
# say anything.
#
# netdisco puts ReverseProxy in the middleware stack unconditionally
# (bin/netdisco-web-fg), so REMOTE_ADDR already holds that same address, and
# the wiki's Configuration page says of behind_proxy that "there's no need to
# touch this". A site that sets it anyway is the only one affected, which is
# consistent with no bug report in the years the defect has been there. The
# setting is honoured rather than ignored because Dancer uses it for scheme,
# host and uri_base as well.

use App::Netdisco;
use App::Netdisco::Web;
use Dancer qw/:syntax :tests/;

sub address_for {
  my ($forwarded, $remote) = @_;
  # PATH_INFO and REQUEST_METHOD are the minimum Dancer::Request needs to
  # build itself; nothing here routes, so their values do not matter.
  my $request = Dancer::Request->new(env => {
    PATH_INFO      => '/',
    REQUEST_METHOD => 'GET',
    REMOTE_ADDR    => $remote,
    (defined $forwarded ? (HTTP_X_FORWARDED_FOR => $forwarded) : ()),
  });
  return $request->remote_address;
}

setting('behind_proxy' => 1);

is address_for('203.0.113.5, 198.51.100.1', '10.0.0.1'),
  '198.51.100.1',
  'address__a_chain_of_two_proxies__is_the_address_the_last_proxy_added';

is address_for('203.0.113.5,198.51.100.1,192.0.2.9', '10.0.0.1'),
  '192.0.2.9',
  'address__a_chain_with_no_spaces__is_still_split_on_the_commas';

is address_for('203.0.113.5', '10.0.0.1'), '203.0.113.5',
  'address__one_proxy__is_unchanged_by_the_override';

is address_for(' 203.0.113.5 ', '10.0.0.1'), '203.0.113.5',
  'address__a_padded_single_address__loses_the_padding';

is address_for(undef, '10.0.0.1'), '10.0.0.1',
  'address__behind_proxy_but_no_header__falls_back_to_the_socket_peer';

is address_for('', '10.0.0.1'), '10.0.0.1',
  'address__an_empty_header__falls_back_to_the_socket_peer';

setting('behind_proxy' => 0);

is address_for('203.0.113.5, 198.51.100.1', '10.0.0.1'), '10.0.0.1',
  'address__behind_proxy_off__ignores_the_header_as_before';

# The consumer this was found through: the value must parse as an address, or
# the token ACL check denies whatever the ACL says.
use NetAddr::IP::Lite;
setting('behind_proxy' => 1);
ok defined NetAddr::IP::Lite->new(address_for('203.0.113.5, 198.51.100.1', '10.0.0.1')),
  'tokenAclClientIp__from_a_forwarded_chain__parses_as_an_address';

done_testing;
