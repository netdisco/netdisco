#!/usr/bin/env perl

# The Ports tab's plugin columns (_extra_device_port_cols) used to be found by
# walking every configured column once per position on every row, checking
# position, whether the user asked for it, and hidden. None of that depends
# on the row, so the route now sorts them once into port_columns_by_position
# and the template walks only those. permitted_by_acl is the one check that
# does depend on the row, and it has to stay in the template.

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::Snapshot qw/render_template stash_for/;

require App::Netdisco::Web::Plugin::Device::Ports;
my $by_position = \&App::Netdisco::Web::Plugin::Device::Ports::_port_columns_by_position;

my @columns = (
  { name => 'cf_left',   field => 'cf_left',   position => 'left' },
  { name => 'cf_mid',    field => 'cf_mid',    position => 'mid' },
  { name => 'cf_right',  field => 'cf_right',  position => 'right' },
  { name => 'cf_left2',  field => 'cf_left2',  position => 'left' },
  { name => 'cf_hidden', field => 'cf_hidden', position => 'left', hidden => 1 },
  { name => 'cf_off',    field => 'cf_off',    position => 'mid' },
  { name => 'cf_nowhere', field => 'cf_nowhere' },
  { name => 'cf_odd',    field => 'cf_odd',    position => 'top' },
);
my %enabled = map { $_ => 1 }
  qw/cf_left cf_mid cf_right cf_left2 cf_hidden cf_nowhere cf_odd/;

subtest 'portColumnsByPosition__asked_for_and_shown__grouped_in_config_order' => sub {
  my $got = $by_position->(\@columns, \%enabled);
  is_deeply [ map { $_->{name} } @{ $got->{left} } ], [qw/cf_left cf_left2/], 'left';
  is_deeply [ map { $_->{name} } @{ $got->{mid} } ], [qw/cf_mid/], 'mid';
  is_deeply [ map { $_->{name} } @{ $got->{right} } ], [qw/cf_right/], 'right';
  is_deeply [ sort keys %$got ], [qw/left mid right/],
    'a column with no position, or one the template has no slot for, is left out';
};

subtest 'portColumnsByPosition__nothing_configured__three_empty_lists' => sub {
  is_deeply $by_position->(undef, \%enabled), { left => [], mid => [], right => [] };
  is_deeply $by_position->(\@columns, {}),    { left => [], mid => [], right => [] },
    'none asked for';
};

# the template side: each column lands in its own slot, and the row's ACL
# still decides whether the cell is drawn
sub render_with {
  my ($permitted) = @_;
  my $stash = stash_for('ajax/device/ports.tt');
  $stash->{params} = { c_port => 1, c_nodes => 1 };
  $stash->{settings}->{_extra_device_port_cols} = \@columns;
  $stash->{port_columns_by_position} = $by_position->(\@columns, \%enabled);
  # no plugin templates exist, so every column takes the plain value cell
  $stash->{port_column_templates} = { map { $_->{name} => 0 } @columns };
  $stash->{permitted_by_acl} = $permitted;
  $stash->{results} = [ { port => 'Gi1/1', up_admin => 'up', up => 'up',
    nodes_search => 'NODES-CELL', get_column => sub { "value-of-$_[0]" } } ];
  my ($html, $error) = render_template('ajax/device/ports.tt', $stash);
  is $error, undef, 'renders' or diag $error;
  return $html // '';
}

subtest 'portsTemplate__plugin_columns__render_in_their_positions' => sub {
  my $html = render_with(sub { 1 });
  my %at = map { $_ => index($html, "value-of-$_") }
    qw/cf_left cf_left2 cf_mid cf_right/;
  my $nodes = index($html, 'data-search="NODES-CELL"');

  ok $at{$_} >= 0, "$_ rendered" for sort keys %at;
  ok $at{cf_left} < $at{cf_left2}, 'left columns keep their config order';
  ok $at{cf_left2} < $at{cf_mid}, 'left before mid';
  ok $at{cf_mid} < $nodes, 'mid before the nodes cell';
  ok $nodes < $at{cf_right}, 'right after the nodes cell';
  unlike $html, qr/value-of-cf_(?:hidden|off|nowhere|odd)/,
    'hidden, unrequested and unplaced columns are not drawn';
};

subtest 'portsTemplate__plugin_column_refused_by_row_acl__not_drawn' => sub {
  my $html = render_with(sub { $_[1]->{name} ne 'cf_mid' });
  unlike $html, qr/value-of-cf_mid/, 'the refused column is not drawn';
  like $html, qr/value-of-cf_left/, 'the others still are';
};

done_testing;
