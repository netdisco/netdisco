#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use Dancer qw/:script !pass/;

use App::Netdisco::Web::PortControl;

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# The queued job action comes from the `field` parameter, but the route
# authorizes only the port_control role, so every field it accepts must be one
# the device and port pages actually offer. A field that reaches the queue
# unresolved names a worker action directly, which is an admin capability.
#
# This targets the sub rather than the route because require_any_role sends the
# request through the DB-backed auth provider, which xt has no database for.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub action_for { return App::Netdisco::Web::PortControl::_action_for_field(@_) }

my %action_map = (
  'location' => 'location',
  'contact'  => 'contact',
  'c_port'   => 'portcontrol',
  'c_name'   => 'portname',
  'c_pvid'   => 'vlan',
  'c_power'  => 'power',
);

subtest 'action_for_field__mapped_field__returns_mapped_action' => sub {
  foreach my $field (sort keys %action_map) {
      is action_for($field), $action_map{$field},
        "$field resolves to the $action_map{$field} action";
  }
};

subtest 'action_for_field__worker_action_name__returns_undef' => sub {
  set('_inline_actions' => ['cf_site', 'cf_ticket']);

  foreach my $field (qw/psql delete renumber pingsweep expire loadmibs
                        show hook nbtstat macsuck arpnip discover/) {
      is action_for($field), undef,
        "$field is not queueable through the port control endpoint";
  }
};

subtest 'action_for_field__mapped_action_name__returns_undef' => sub {
  set('_inline_actions' => ['cf_site']);

  # the allow list is keyed on the field names the views render, not on the
  # action names those fields map to
  foreach my $action (sort values %action_map) {
      next if exists $action_map{$action};
      is action_for($action), undef, "$action is not itself an accepted field";
  }
};

subtest 'action_for_field__configured_custom_field__returns_that_field' => sub {
  set('_inline_actions' => ['cf_site', 'cf_ticket']);

  is action_for('cf_site'), 'cf_site', 'configured custom field is accepted';
  is action_for('cf_ticket'), 'cf_ticket', 'second custom field is accepted';
  is action_for('cf_absent'), undef, 'unconfigured custom field is rejected';
};

subtest 'action_for_field__custom_field_not_configured__returns_undef' => sub {
  set('_inline_actions' => []);
  is action_for('cf_site'), undef, 'empty inline actions accepts no cf_ field';

  set('_inline_actions' => undef);
  is action_for('cf_site'), undef, 'unset inline actions accepts no cf_ field';
  is action_for('c_port'), 'portcontrol', 'mapped fields survive the unset';
};

subtest 'action_for_field__empty_or_missing_field__returns_undef' => sub {
  set('_inline_actions' => ['cf_site']);

  is action_for(undef), undef, 'no field at all is rejected';
  is action_for(''), undef, 'empty field is rejected';
  is action_for('device_port_custom_field_site'), undef,
    'device_port_custom_field_ prefix is not an accepted field';
};

done_testing;
