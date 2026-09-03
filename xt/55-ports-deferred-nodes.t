#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::Snapshot qw/render_template stash_for/;

# The committed snapshot cannot guard this: it leaves uri_for unstubbed, so
# the route in the hx-get attribute renders blank there, and a snapshot only
# records that some byte changed, not which element the change landed on.
# This drives the over-threshold row directly and supplies uri_for as an
# identity function to read the actual attributes and their placement.

my $stash = stash_for('ajax/device/ports.tt');
$stash->{uri_for} = sub { $_[0] };
$stash->{device} = { ip => '10.0.0.1' };

my ($html, $error) = render_template('ajax/device/ports.tt', $stash);
is $error, undef, 'renders' or diag $error;

like $html, qr/hx-get="[^"]*\/ajax\/content\/device\/port\/nodes[^"]*"/,
  'the deferred block fetches the one-port route';
like $html, qr/hx-headers='\{"X-Requested-With": "XMLHttpRequest"\}'/,
  'the deferred block sends the XHR header';
like $html, qr/hx-target="this"/, 'it swaps into itself';
like $html, qr/hx-trigger="[^"]*once[^"]*"/, 'it fetches once, not per click';

# Every attribute on the element itself. htmx 4.0 makes inheritance explicit,
# so an attribute inherited from a parent will not survive that upgrade.
my ($div) = $html =~ m/(<div class="nd_collapsing[^>]*>)/;
like $div, qr/hx-get=/,     'hx-get is on the div, not inherited';
like $div, qr/hx-headers=/, 'hx-headers is on the div, not inherited';

# The regexes above match on the route path alone and would still pass if
# the n_*/mac_format suffix were silently dropped: _deferred_node_params
# builds that string in Perl, but the template just interpolates it
# unfiltered, relying on AUTO_FILTER to html-escape it in the attribute.
$stash->{deferred_node_params} = '&n_dns=1&mac_format=cisco';
my ($html2, $error2) = render_template('ajax/device/ports.tt', $stash);
is $error2, undef, 'renders with deferred_node_params set' or diag $error2;
like $html2, qr/hx-get="[^"]*&amp;n_dns=1&amp;mac_format=cisco"/,
  'deferred_node_params lands in hx-get, html-escaped';

done_testing;
