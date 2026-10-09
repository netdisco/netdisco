#!/usr/bin/env perl

# The Ports tab shows a VLAN by its number, its name, or both, as the "Show
# VLANs as" choice in the sidebar says (p_vlan_display), and the Native VLAN cell
# is a picker over the device's own VLANs. The route sends the menu's rows once
# for the page, as JSON in a script block, and each editable row carries only
# the field: the label it shows, and the VLAN number it stands for, which is
# what a change sends back.
#
# What a label is comes from one function, which the route also hands to the
# templates, so these check it on its own and then through the templates.
#
# Needs no database and no session, like xt/56-ports-deferred-nodes.t: the rows
# are built by functions of plain hashes, and the cells are rendered from a stash.

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::Snapshot qw/render_template stash_for/;

require App::Netdisco::Web::Plugin::Device::Ports;

sub label   { App::Netdisco::Web::Plugin::Device::Ports::_vlan_label(@_) }
sub display { App::Netdisco::Web::Plugin::Device::Ports::_vlan_display(@_) }

subtest 'vlanDisplay__a_known_choice__is_kept' => sub {
  is display($_), $_, "$_ is kept" for qw/id name both/;
};

subtest 'vlanDisplay__no_choice_or_an_unknown_one__is_the_number' => sub {
  is display(undef), 'id', 'no choice';
  is display(''), 'id', 'an empty choice';
  is display('on'), 'id', 'what the old Use VLAN Names checkbox sent';
  is display('name; DROP TABLE'), 'id', 'anything else';
};

subtest 'vlanLabel__a_named_vlan__is_shown_as_the_choice_says' => sub {
  is label('id',   10, 'office'), 10,            'id: the number';
  is label('name', 10, 'office'), 'office',      'name: the name';
  is label('both', 10, 'office'), 'office (10)', 'both: the name and the number';
};

subtest 'vlanLabel__a_vlan_without_a_name__is_always_the_number' => sub {
  for my $display (qw/id name both/) {
    is label($display, 10, undef), 10, "$display, no name";
    is label($display, 10, ''),    10, "$display, empty name";
    is label($display, 10, '10'),  10, "$display, a name that is only the number";
  }
};

my @vlans = (
  { vlan => 10, description => 'office' },
  { vlan => 20, description => '' },
);

subtest 'vlanChoices__every_choice__keeps_the_number_as_the_value' => sub {
  for my $display (qw/id name both/) {
    my $rows = App::Netdisco::Web::Plugin::Device::Ports::_vlan_choices(\@vlans, $display);
    is_deeply [ map { "$_->{value}" } @$rows ], [10, 20], "$display: the value is the number";
  }
};

subtest 'vlanChoices__the_label__is_what_the_table_shows' => sub {
  my $labels = sub {
    my $rows = App::Netdisco::Web::Plugin::Device::Ports::_vlan_choices(\@vlans, shift);
    return [ map { "$_->{label}" } @$rows ];
  };
  is_deeply $labels->('id'),   [10, 20],              'id';
  is_deeply $labels->('name'), ['office', 20],        'name';
  is_deeply $labels->('both'), ['office (10)', 20],   'both';
};

# One port that the user may change, as the route marks it, over the page's own
# fixture, so the rest of the template renders as it does in the snapshot.
sub render_ports {
  my ($display, $row) = @_;
  my $stash = stash_for('ajax/device/ports.tt');
  $stash->{vlan_display} = $display;
  $stash->{vlan_label} = sub { label($display, @_) };
  $stash->{results} = [ { port => 'Gi1/1', up_admin => 'up', port_acl_pvid => 1, %$row } ];
  my ($html, $error) = render_template('ajax/device/ports.tt', $stash);
  is $error, undef, 'renders' or diag $error;
  return $html;
}

my $FIELD = qr/<input type="text" class="nd_pvid-search"[^>]*\bvalue="([^"]*)"/;

subtest 'portsTemplate__each_choice__the_field_shows_what_the_choice_says_and_keeps_the_number' => sub {
  my %want = (id => '10', name => 'office', both => 'office (10)');
  for my $display (qw/id name both/) {
    my $html = render_ports($display, { vlan => 10, native_vlan_name => 'office' });
    my ($shown) = $html =~ $FIELD;
    is $shown, $want{$display}, "$display: the field shows it";
    like $html, qr/\bdata-vlan="10"/, "$display: the field keeps the number";
    like $html, qr/\bdata-filter="\Q$want{$display}\E"/, "$display: the table filters on what it shows";
  }
};

subtest 'portsTemplate__a_vlan_with_no_name__the_field_shows_the_number' => sub {
  for my $display (qw/name both/) {
    my ($shown) = render_ports($display, { vlan => 10 }) =~ $FIELD;
    is $shown, '10', $display;
  }
};

subtest 'portsTemplate__a_port_with_no_vlan__the_field_is_empty' => sub {
  my $html = render_ports('both', { vlan => 0 });
  my ($shown) = $html =~ $FIELD;
  is $shown, '', 'the field shows nothing';
  like $html, qr/\bdata-vlan=""/, 'and keeps no number, so nothing is sent for it';
};

subtest 'portsTemplate__a_port_the_user_cannot_change__the_cell_follows_the_choice_and_links_to_the_vlan' => sub {
  my %want = (id => '10', name => 'office', both => 'office (10)');
  for my $display (qw/id name both/) {
    my $html = render_ports($display, { vlan => 10, native_vlan_name => 'office', port_acl_pvid => 0 });
    my ($q, $text) = $html =~ m{<a class="nd_linkcell"\s+href="[^"]*\?tab=vlan&q=([^"]*)">\s*([^<]*?)\s*</a>};
    is $text, $want{$display}, "$display: the link shows it";
    # a name is searched by name, so that one search finds it on every device
    is $q, ($display eq 'name' ? 'office' : '10'), "$display: and searches for the right thing";
  }
};

subtest 'portsTemplate__the_vlans_of_a_port__follow_the_choice' => sub {
  my %want = (id => '10, 20', name => 'office, 20', both => 'office (10), 20');
  for my $display (qw/id name both/) {
    my $stash = stash_for('ajax/device/ports.tt');
    $stash->{vlan_display} = $display;
    $stash->{vlan_label} = sub { label($display, @_) };
    $stash->{vlans} = { 'Gi1/1' => { vlan_count => 2, vlan_set => [10, 20],
                                     vlan_name_set => ['office', '20'] } };
    $stash->{results} = [ { port => 'Gi1/1', up_admin => 'up' } ];
    my ($out, $error) = render_template('ajax/device/ports.tt', $stash);
    is $error, undef, 'renders' or diag $error;
    my @links = $out =~ m{<a href="[^"]*\?tab=vlan&q=[^"]*">([^<]*)</a>}g;
    is join(', ', @links), $want{$display}, $display;
  }
};

subtest 'portsTemplate__a_vlan_name_is_markup__it_cannot_leave_its_attribute_or_the_script_block' => sub {
  my $stash = stash_for('ajax/device/ports.tt');
  my $name = q{x"><b>bold</b></script><script>evil()</script>};
  $stash->{vlan_display} = 'name';
  $stash->{vlan_label} = sub { label('name', @_) };
  $stash->{vlan_choices} = Dancer::to_json([ { label => $name, value => 10 } ]);
  $stash->{results} = [ { port => 'Gi1/1', up_admin => 'up', port_acl_pvid => 1,
    vlan => 10, native_vlan_name => $name } ];
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
