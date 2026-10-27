#!/usr/bin/env perl

# A device port link whose url is only the variables a link can be given is
# drawn by the browser, which is told the url once and the device's own values
# once, and each port's own from its row. Anything else in a url needs
# Template Toolkit, and then the server draws the links, as it always did.
#
# What is here is the server's half: which links the browser may draw, what it
# is given for the device (escaped as externallinks.tt escaped it), and which
# ports a link's only/no ACL hides it from. The drawing is tested in
# xt/js/ports-table.test.js.
#
# Needs no database and no session.

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::PortsJSON qw/fake_row/;

require App::Netdisco::Web::Plugin::Device::Ports;

subtest 'links__a_url_of_only_the_ports_variables__is_drawn_by_the_browser' => sub {
  my $simple = sub { App::Netdisco::Web::Plugin::Device::Ports::_simple_links(\@_) };
  ok $simple->({ url => 'https://g/d?d=[% device %]&p=[%port%]&i=[%  ifindex  %]', displayname => 'G' }),
    'the variables, with or without spaces';
  ok $simple->({ url => 'https://static/', displayname => 'S' }), 'no variables at all';
  ok !$simple->({ url => 'https://g/[% cf_rack %]', displayname => 'G' }), 'a custom field needs the server';
  ok !$simple->({ url => 'https://g/[% port.lower %]', displayname => 'G' }), 'a method call does';
  ok !$simple->({ url => 'https://g/[% IF port %]x[% END %]', displayname => 'G' }), 'so does a directive';
  ok !$simple->({ url => 'https://g/[% device %]', displayname => 'G' }, { url => '[% port | upper %]' }),
    'one link that does makes the server draw them all';
  ok !App::Netdisco::Web::Plugin::Device::Ports::_simple_links([]), 'no links, none to draw';
};

subtest 'links__the_devices_values__are_escaped_as_externallinks_tt_escaped_them' => sub {
  my $device = bless { ip => '192.0.2.1', dns => 'sw1.example.com', name => 'sw 1/a' }, 'Test::Dev';
  { no strict 'refs'; *{"Test::Dev::$_"} = do { my $k = $_; sub { $_[0]->{$k} } } for qw/ip dns name/; }
  my $vars = App::Netdisco::Web::Plugin::Device::Ports::_device_link_vars($device, '.example.com');
  is_deeply $vars, { device => '192.0.2.1', fqdn => 'sw1.example.com', sysname => 'sw%201%2Fa', hostname => 'sw1' };
};

subtest 'links__a_port_the_acl_hides_a_link_from__lists_it_as_off' => sub {
  my $links = [ { url => 'a', displayname => 'A' }, { url => 'b', displayname => 'B', no => ['port:Vlan.*'] } ];
  my $row = fake_row({ port => 'Vlan10', up_admin => 'up' });
  my $json = App::Netdisco::Web::Plugin::Device::Ports::_port_json($row, { p => { c_links => 1 }, links => $links });
  is_deeply $json->{links_off}, [1], 'the second link, by its place in meta.links';
  my $other = fake_row({ port => 'Gi1/1', up_admin => 'up' });
  ok !exists App::Netdisco::Web::Plugin::Device::Ports::_port_json($other, { p => { c_links => 1 }, links => $links })->{links_off},
    'and nothing for a port that sees both';
};

done_testing;
