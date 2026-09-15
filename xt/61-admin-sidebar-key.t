#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;

# The sidebar options of a page are keyed on the last two segments of its
# path, and the admin pages are served from /admin/<task> while share/config.yml
# and the sidebar templates key them under admintask_<task>. Nothing joined
# the two, so the before_template hook that folds the URL parameters into the
# defaults looked up a key that does not exist and did nothing, and the ACL
# editor's Host Preference always rendered as the configured default whatever
# the address said.
#
# That is why the entry links carry firstsearch=on, which is what the reports
# menu in the layout has always done: the fold is an overwrite, so a link that
# names no options would otherwise blank them.
#
# The probe route is registered here rather than reused from lib/, so the test
# needs no database and no admin user: every real admin page is behind
# require_role. `no_auth` makes the AuthN `before` hook synthesize a guest
# session rather than rewrite path_info to '/', which is the same reason
# xt/57-route-cache-ajax.t sets it.
#
# It is the pane path rather than the page path because App::Netdisco::Web
# registers a catch-all for everything outside /ajax/, and a route registered
# later never sees those. The key is derived from the last two segments, which
# are the same either way.

BEGIN {
    $ENV{DANCER_ENVIRONMENT} = 'testing';
}

use App::Netdisco;
use App::Netdisco::Web;
use Dancer qw/:syntax :tests/;
use Dancer::Test;
use Dancer::Plugin::Ajax;
use Dancer::Factory::Hook;

setting('no_auth' => 1);
setting('sidebar_defaults')->{'admintask_xtsidebarprobe'}
  = { aclhost => { default => 'ip' } };

# The fold runs when a template is rendered, and rendering an admin page needs
# a database, so the probe runs the hooks the renderer would have run and
# reports what they left behind.
ajax '/ajax/content/admin/xtsidebarprobe' => sub {
    Dancer::Factory::Hook->execute_hooks('before_template_render', {});
    return join ' ', var('sidebar_key'),
      (var('sidebar_defaults')->{'admintask_xtsidebarprobe'}->{'aclhost'} // 'unset');
};

sub probe {
    my $query = shift;
    local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
    return dancer_response(GET => '/ajax/content/admin/xtsidebarprobe'. $query);
}

subtest 'sidebar_key__an_admin_path__is_the_key_the_configuration_uses' => sub {
    my $r = probe('?firstsearch=on');

    like $r->content, qr/^admintask_xtsidebarprobe /,
      'the key an admin path derives names the admintask family';

    is_deeply [ grep { m/_acleditor$/ } keys %{ setting('sidebar_defaults') } ],
      [ 'admintask_acleditor' ],
      'which is the family share/config.yml keys the ACL editor under';
};

subtest 'sidebar_defaults__admin_address_with_an_option__take_it_from_the_url' => sub {
    my $r = probe('?aclhost=name');

    is $r->content, 'admintask_xtsidebarprobe name',
      'the address decides what the sidebar renders as chosen';
};

subtest 'sidebar_defaults__admin_address_from_a_link__keeps_the_default' => sub {
    my $r = probe('?firstsearch=on');

    is $r->content, 'admintask_xtsidebarprobe ip',
      'a link naming no options leaves the configured default in place';
};

# Recorded rather than wanted: this is the shape of address the fold blanks,
# and the reason the layout and the ACL manager link with firstsearch=on.
subtest 'sidebar_defaults__admin_address_with_no_options__are_blanked' => sub {
    my $r = probe('');

    is $r->content, 'admintask_xtsidebarprobe unset',
      'an address naming no options at all says none is chosen';
};

done_testing;
