#!/usr/bin/env perl

# The Native VLAN cell on the Ports tab is a picker over the device's own VLANs.
# The route sends the menu's rows once for the page, as JSON in a script block,
# and each editable row carries only the field: the label it shows, and the VLAN
# number it stands for, which is what a change sends back.
#
# What the label is follows the page's own "Use VLAN Names" option, as the
# read-only cell and the CSV do: the name when it is set, the number otherwise.
# It is never both, which is why these check the label and the number apart.
#
# Needs no database and no session, like xt/56-ports-deferred-nodes.t: the rows
# are built by a function of plain hashes, and the cell is rendered from a stash.

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::Snapshot qw/render_template stash_for/;

require App::Netdisco::Web::Plugin::Device::Ports;

my @vlans = (
  { vlan => 10, description => 'office' },
  { vlan => 20, description => '' },
  { vlan => 30, description => undef },
);

subtest 'vlanChoices__names_off__labels_are_the_numbers' => sub {
  my $rows = App::Netdisco::Web::Plugin::Device::Ports::_vlan_choices(\@vlans, 0);
  is_deeply [ map { "$_->{label}" } @$rows ], [10, 20, 30], 'every label is its number';
  is_deeply [ map { "$_->{value}" } @$rows ], [10, 20, 30], 'every value is its number';
};

subtest 'vlanChoices__names_on__labels_are_the_names_with_the_number_for_an_unnamed_vlan' => sub {
  my $rows = App::Netdisco::Web::Plugin::Device::Ports::_vlan_choices(\@vlans, 1);
  is_deeply [ map { "$_->{label}" } @$rows ], ['office', 20, 30],
    'an empty or missing name is shown as the number, as the VLAN list of a port does';
  is_deeply [ map { "$_->{value}" } @$rows ], [10, 20, 30],
    'the value is still the number, because that is what the port is set to';
};

# One port that the user may change, as the route marks it, over the page's own
# fixture, so the rest of the template renders as it does in the snapshot.
sub render_picker {
  my ($params, $row) = @_;
  my $stash = stash_for('ajax/device/ports.tt');
  $stash->{params} = { %{ $stash->{params} }, %$params };
  $stash->{results} = [ { port => 'Gi1/1', up_admin => 'up', port_acl_pvid => 1, %$row } ];
  my ($html, $error) = render_template('ajax/device/ports.tt', $stash);
  is $error, undef, 'renders' or diag $error;
  return $html;
}

subtest 'portsTemplate__names_off__the_field_shows_the_number' => sub {
  my $html = render_picker({}, { vlan => 10 });
  like $html, qr/<input type="text" class="nd_pvid-search"[^>]*\bvalue="10"/, 'the field shows the number';
  like $html, qr/\bdata-vlan="10"/, 'the field keeps the number';
};

subtest 'portsTemplate__names_on__the_field_shows_the_name_and_keeps_the_number' => sub {
  my $html = render_picker({ p_vlan_names => 1 },
    { vlan => 10, get_column => sub { 'office' } });
  like $html, qr/<input type="text" class="nd_pvid-search"[^>]*\bvalue="office"/, 'the field shows the name';
  like $html, qr/\bdata-vlan="10"/, 'the field keeps the number';
  like $html, qr/\bdata-filter="office"/, 'the table filters on what the field shows';
  unlike $html, qr/office \(10\)/, 'the name and number are not shown together';
};

subtest 'portsTemplate__names_on_and_the_vlan_has_no_name__the_field_shows_the_number' => sub {
  my $html = render_picker({ p_vlan_names => 1 },
    { vlan => 10, get_column => sub { undef } });
  like $html, qr/<input type="text" class="nd_pvid-search"[^>]*\bvalue="10"/, 'the number stands in';
};

subtest 'portsTemplate__a_port_with_no_vlan__the_field_is_empty' => sub {
  my $html = render_picker({}, { vlan => 0 });
  like $html, qr/<input type="text" class="nd_pvid-search"[^>]*\bvalue=""/, 'the field shows nothing';
  like $html, qr/\bdata-vlan=""/, 'and keeps no number, so nothing is sent for it';
};

subtest 'portsTemplate__a_vlan_name_is_markup__it_cannot_leave_its_attribute_or_the_script_block' => sub {
  my $stash = stash_for('ajax/device/ports.tt');
  my $name = q{x"><b>bold</b></script><script>evil()</script>};
  $stash->{params}->{p_vlan_names} = 1;
  $stash->{vlan_choices} = Dancer::to_json([ { label => $name, value => 10 } ]);
  $stash->{results} = [ { port => 'Gi1/1', up_admin => 'up', port_acl_pvid => 1,
    vlan => 10, get_column => sub { $name } } ];
  my ($html, $error) = render_template('ajax/device/ports.tt', $stash);
  is $error, undef, 'renders' or diag $error;

  my ($block) = $html =~ m{<script type="application/json" id="nd-vlan-choices">(.*?)</script>}s;
  ok defined $block, 'the menu rows are in one script block';
  unlike $block, qr/</, 'no "<" is left in it to end the element early';
  like $block, qr/\\u003c/i, 'each is its JSON escape, which JSON.parse reads back as "<"';
  unlike $html, qr/<script>evil\(\)/, 'the name never becomes a script';
  unlike $html, qr/value="x"><b>/, 'and never closes the field\'s attribute';
};

subtest 'portsTemplate__no_menu_rows_sent__no_script_block' => sub {
  my $stash = stash_for('ajax/device/ports.tt');
  delete $stash->{vlan_choices};
  my ($html, $error) = render_template('ajax/device/ports.tt', $stash);
  is $error, undef, 'renders' or diag $error;
  unlike $html, qr/nd-vlan-choices/, 'a user who cannot change a VLAN is not sent the list';
};

done_testing;
