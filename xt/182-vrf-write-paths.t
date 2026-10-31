#!/usr/bin/env perl

use strict;
use warnings;

# device_ip and subnets keys include vrf, so every writer must name it, and
# a two-key DeviceIp->find would now die on the wider primary key.
#
# Only the upsert is faked; the pseudo-device and renumber guards read source.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Path::Tiny;
use App::Netdisco;
use Dancer ':tests';
use App::Netdisco::DB;

set logger => 'null';

my $schema = do {
  local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /unversioned/ };
  App::Netdisco::DB->clone;
};

my @captured;
{
  no warnings qw(redefine once);
  local *App::Netdisco::DB::ResultSet::upsert = sub { push @captured, $_[1]; 1 };

  subtest 'upsert_subnet__no_vrf__upserts_net_with_empty_vrf' => sub {
    @captured = ();
    $schema->resultset('Subnet')->upsert_subnet('192.0.2.0/24', 'LOCALTIMESTAMP');
    is scalar @captured, 1, 'one upsert';
    is $captured[0][0]{net}, '192.0.2.0/24';
    is $captured[0][0]{vrf}, '', 'vrf is empty string';
  };

  subtest 'upsert_subnet__vrf_given__upserts_that_vrf' => sub {
    @captured = ();
    $schema->resultset('Subnet')->upsert_subnet('192.0.2.0/24', 'LOCALTIMESTAMP', 'red');
    is $captured[0][0]{vrf}, 'red';
  };
}

subtest 'pseudo_device__device_ip_row__has_empty_vrf' => sub {
  for my $file (qw(
    lib/App/Netdisco/Worker/Plugin/AddPseudoDevice.pm
    lib/App/Netdisco/Web/Plugin/AdminTask/PseudoDevice.pm
  )) {
    my $source = Path::Tiny::path($file)->slurp_utf8;
    like $source,
      qr/resultset\('DeviceIp'\)\s*->create\(\{[^}]*\bvrf\s*=>\s*''/s,
      "$file creates the device_ip row with vrf => ''";
  }
};

subtest 'renumber__dns_lookup__does_not_call_find_with_two_keys' => sub {
  my $source = Path::Tiny::path('lib/App/Netdisco/DB/Result/Device.pm')->slurp_utf8;
  unlike $source, qr/resultset\('DeviceIp'\)\s*->find\(\s*[^{)][^)]*,/,
    'Device.pm does not call DeviceIp->find with two positional keys';
  like $source, qr/resultset\('DeviceIp'\)->search\(\{ ip => \$new_ip, alias => \$new_ip \}\)/,
    'renumber looks the row up with search';
};

done_testing;
