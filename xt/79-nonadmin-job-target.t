#!/usr/bin/env perl

use strict;
use warnings;

# The nonadmin control routes accept a device from any logged in user and
# queue a backend job for it, so the target must be a single address the
# inventory already holds.
#
# nonadmin_job_target() is that decision in two halves: single_address(),
# which is asserted here, and a lookup of the result in the device table,
# which is not, because these routes are registered only under
# enable_nonadmin_actions and the lookup needs a live database.
#
# The source assertions at the end cover the two things the unit tests cannot:
# that both route bodies still consult the gate, and that neither forwards a
# request parameter the backend would merge into its own configuration.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use Dancer qw/:script !pass/;
use App::Netdisco::Web::AdminTask;

my $single_address = \&App::Netdisco::Web::AdminTask::single_address;

is($single_address->('192.0.2.1'), '192.0.2.1',
  'single_address__bare_ipv4__returns_the_address');

is($single_address->('192.0.2.1/32'), '192.0.2.1',
  'single_address__ipv4_with_host_masklen__returns_the_address');

is($single_address->('2001:db8::1'), '2001:db8:0:0:0:0:0:1',
  'single_address__bare_ipv6__returns_the_normalized_address');

is($single_address->('2001:db8::1/128'), '2001:db8:0:0:0:0:0:1',
  'single_address__ipv6_with_host_masklen__returns_the_normalized_address');

is($single_address->('192.0.2.0/24'), undef,
  'single_address__ipv4_prefix__is_refused');

is($single_address->('10.0.0.0/22'), undef,
  'single_address__widest_prefix_add_job_allows_for_discover__is_refused');

is($single_address->('192.0.2.0/31'), undef,
  'single_address__narrowest_ipv4_prefix__is_refused');

is($single_address->('2001:db8::/64'), undef,
  'single_address__ipv6_prefix__is_refused');

# resolved by /etc/hosts, so a build with no working DNS still runs this
is($single_address->('localhost'), undef,
  'single_address__hostname__is_refused');

is($single_address->('default'), undef,
  'single_address__netaddr_ip_shorthand__is_refused');

is($single_address->('not an address'), undef,
  'single_address__garbage__is_refused');

is($single_address->(''), undef,
  'single_address__empty_string__is_refused');

is($single_address->(undef), undef,
  'single_address__missing_device__is_refused');

my $source = do {
  open my $fh, '<', $INC{'App/Netdisco/Web/AdminTask.pm'}
    or die "cannot read AdminTask.pm: $!";
  local $/; <$fh>;
};

my ($nonadmin_routes) =
  ($source =~ m/^if \(setting\('enable_nonadmin_actions'\)\) \{(.*?)^\}/ms);

ok($nonadmin_routes, 'nonadmin_routes__module_source__are_registered_in_one_block');

is(scalar(() = $nonadmin_routes =~ m/nonadmin_job_target/g), 2,
  'nonadmin_routes__ajax_and_post__both_check_the_job_target');

is(scalar(() = $nonadmin_routes =~ m/add_job\(\$action, param\('device'\)\)/g), 2,
  'nonadmin_routes__ajax_and_post__queue_the_device_alone');

unlike($nonadmin_routes, qr/param\('(?:extra|port)'\)/,
  'nonadmin_routes__ajax_and_post__forward_neither_extra_nor_port');

done_testing;
