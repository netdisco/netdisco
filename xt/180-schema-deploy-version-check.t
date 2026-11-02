use strict;
use warnings;

# netdisco-db-deploy opens a database it is about to upgrade. DBIC's
# connect-time version check then carps "Versions out of sync ... please call
# upgrade on your Schema" from inside DBICx::Sugar, telling the user to do what
# the deploy is already doing (#1788). Nothing listens on port 1, so the check
# fails fast and no test needs a database: DBIC still carps "currently
# unversioned" for it.
BEGIN {
  $ENV{DANCER_ENVDIR} = '/dev/null';
  $ENV{PGHOST} = '127.0.0.1';
  $ENV{PGPORT} = 1;
}

use Test::More 0.88;
use App::Netdisco;
use Dancer qw/:script :tests/;
use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::DB::Deploy qw(deploy_schema);

set logger => 'null';

sub warnings_from (&) {
  my $code = shift;
  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, @_ };
  $code->();
  return @warnings;
}

# without this the subtest below could pass because nothing carps at all
subtest 'schema__database_unreachable__carps_the_version_check' => sub {
  my @warnings = warnings_from { schema('netdisco') };
  ok((grep { /DBIx::Class::Schema::Versioned/ } @warnings), 'the plain schema runs the check');
};

subtest 'deploy_schema__database_unreachable__opens_without_version_check' => sub {
  my @warnings = warnings_from { deploy_schema() };
  is_deeply(\@warnings, [], 'no DBIC version carp from the deploy schema');
};

subtest 'deploy_schema__default_label__connects_where_schema_netdisco_does' => sub {
  my ($deploy, $plain);
  warnings_from { $deploy = deploy_schema(); $plain = schema('netdisco') };
  is($deploy->storage->connect_info->[0], $plain->storage->connect_info->[0], 'same DSN');
};

# the web and backend share this config, and for them the check is the only
# sign of a missed upgrade
subtest 'deploy_schema__after_use__leaves_the_shared_config_checking' => sub {
  warnings_from { deploy_schema() };
  my $dbic = setting('plugins')->{DBIC};
  my @labels = grep { ref $dbic->{$_} eq 'HASH' } keys %$dbic;
  ok(scalar @labels, 'there is DBIC config to check');
  ok(!$dbic->{$_}->{options}->{ignore_version}, "$_ still runs the check") for @labels;
};

# the script dies when it reaches the database; the carp came before that
subtest 'netdisco_db_deploy__database_unreachable__prints_no_version_check' => sub {
  my $output = `"$^X" -Ilib bin/netdisco-db-deploy 2>&1`;
  isnt($?, 0, 'the deploy stops: nothing listens on port 1');
  unlike($output, qr/DBIx::Class::Schema::Versioned/, 'no DBIC version carp in its output');
};

done_testing;
