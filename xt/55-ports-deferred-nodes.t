#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::Snapshot qw/render_template stash_for/;

# Needs no database and no session: _deferred_node_params is free of
# param(), so this and the assertions below that call it directly belong
# outside any SKIP block, alongside xt/53's own param-free checks.
require App::Netdisco::Web::Plugin::Device::Ports;

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

# The assertion above sets $stash->{deferred_node_params} directly and never
# calls _deferred_node_params itself, so it cannot catch a regression inside
# that function (deleting its mac_format branch entirely, for instance).
# These call it directly instead.
my $qs_some = App::Netdisco::Web::Plugin::Device::Ports::_deferred_node_params(
  1, 0, 1, 0, 1, 0, 0, 0, 'Cisco');
like $qs_some, qr/&n_ip4=1/,  'n_ip4 on is carried';
like $qs_some, qr/&n_dns=1/,  'n_dns on is carried';
like $qs_some, qr/&n_ssid=1/, 'n_ssid on is carried';
like $qs_some, qr/&mac_format=Cisco/, 'mac_format is carried';

for my $mac_format (undef, '') {
    my $qs_no_mac = App::Netdisco::Web::Plugin::Device::Ports::_deferred_node_params(
      1, 1, 1, 1, 1, 1, 1, 1, $mac_format);
    unlike $qs_no_mac, qr/mac_format/,
      'a ' . (defined $mac_format ? 'empty' : 'undef')
      . ' mac_format is omitted, not emitted empty';
}

# Every option carried when true, not just the ones the calls above happen
# to set truthy: one all-true call, checked in a loop over all eight, so a
# regression in any single option's line is caught rather than assumed
# covered by a different assertion's incidental truthy value.
my $qs_all = App::Netdisco::Web::Plugin::Device::Ports::_deferred_node_params(
  1, 1, 1, 1, 1, 1, 1, 1, 'IEEE');
for my $option (qw/n_ip4 n_ip6 n_dns n_age n_ssid n_vendor n_netbios n_archived/) {
    like $qs_all, qr/&\Q$option\E=1/, "$option on is carried";
}

# Truthiness as Perl itself defines it, not as HTML checkboxes happen to
# submit it: 'on' and 'off' are both non-empty strings, so both are true;
# only '0', '', and undef are false. The deferred fetch has to agree with
# every other truthiness check in Ports.pm's route handler, where param()
# results are used the same bare way, or its markup stops matching the
# eager path's.
my $qs_truthy = App::Netdisco::Web::Plugin::Device::Ports::_deferred_node_params(
  'on', 0, 1, '', 'off', '0', undef, 1, undef);
like   $qs_truthy, qr/&n_ip4=1/,     'a truthy string ("on") is carried';
unlike $qs_truthy, qr/&n_ip6=1/,     'the number 0 is not carried';
like   $qs_truthy, qr/&n_dns=1/,     'the number 1 is carried';
unlike $qs_truthy, qr/&n_age=1/,     'an empty string is not carried';
like   $qs_truthy, qr/&n_ssid=1/,    'the string "off" is still true and is carried';
unlike $qs_truthy, qr/&n_vendor=1/,  'the string "0" is not carried';
unlike $qs_truthy, qr/&n_netbios=1/, 'undef is not carried';
like   $qs_truthy, qr/&n_archived=1/, 'a truthy number (1) is carried';
is scalar(() = $qs_truthy =~ /&n_ip4=1/g), 1, 'a carried option appears exactly once';

done_testing;
