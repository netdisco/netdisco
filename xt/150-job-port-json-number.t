#!/usr/bin/env perl

# A port name that is also a valid JSON number (ERS "1.10") must reach the job
# as written, not as the number from_json makes of it ("1.1").

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::Backend::Job;
use App::Netdisco::Util::Configuration 'split_params_to_config';

use Dancer qw/:moose :script !pass/;

config->{logger} = 'null';

subtest 'split_params_to_config__json_number_port__keeps_the_text' => sub {
foreach my $port (qw/1.10 1.0 2.20 0.50 10 1e0 true/) {
  my ($value, $overrides) = split_params_to_config($port);
  is $value, $port, "$port is returned as written";
  is $overrides, undef, "$port carries no overrides";
}
};

subtest 'split_params_to_config__other_ports__unchanged' => sub {
foreach my $port ('Gi1/0/10', '1/10', '007') {
  is +(split_params_to_config($port))[0], $port, "$port is returned as written";
}
};

subtest 'split_params_to_config__quoted_json_string__is_decoded' => sub {
is +(split_params_to_config('"unchanged"'))[0], 'unchanged',
  'a quoted JSON string gives its content';
};

subtest 'split_params_to_config__value_with_number_text__keeps_the_text' => sub {
my ($value, $overrides) =
  split_params_to_config('{"value": "1.10", "with": {"snmptimeout": 5000000}}');
is $value, '1.10', 'the value is returned as written';
is_deeply $overrides, { snmptimeout => 5000000 }, 'the override is still found';
};

subtest 'job_new__json_number_port__keeps_the_text' => sub {
my $job = App::Netdisco::Backend::Job->new({
  job => 42,
  device => '192.0.2.1',
  action => 'portcontrol',
  port => '1.10',
});
$job->apply_config_overrides;
is $job->port, '1.10', 'the job port is as queued';
};

done_testing;
