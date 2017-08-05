package App::Netdisco::Core::Plugin::Expire::Main::RFC;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';

use Time::Piece;
use App::Netdisco::Backend::Util ':all';

use App::Netdisco::Core::Plugin;

# expire devices and nodes according to config
register_core_worker({ driver => 'any' } => sub {
  my ($job, $workerconf) = @_;

  if (setting('expire_devices') and setting('expire_devices') > 0) {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('Device')->search({
          -or => [ 'vendor' => undef, 'vendor' => { '!=' => 'netdisco' }],
          last_discover => \[q/< (now() - ?::interval)/,
              (setting('expire_devices') * 86400)],
        })->delete();
        die; # XXX
      });
  }

  if (setting('expire_nodes') and setting('expire_nodes') > 0) {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('Node')->search({
          time_last => \[q/< (now() - ?::interval)/,
              (setting('expire_nodes') * 86400)],
        })->delete();
        die; # XXX
      });
  }

  if (setting('expire_nodes_archive') and setting('expire_nodes_archive') > 0) {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('Node')->search({
          -not_bool => 'active',
          time_last => \[q/< (now() - ?::interval)/,
              (setting('expire_nodes_archive') * 86400)],
        })->delete();
        die; # XXX
      });
  }

  if (setting('expire_jobs') and setting('expire_jobs') > 0) {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('Admin')->search({
          entered => \[q/< (now() - ?::interval)/,
              (setting('expire_jobs') * 86400)],
        })->delete();
        die; # XXX
      });
  }

  # now update stats
  my $schema = schema('netdisco');
  eval { require SNMP::Info };
  my $snmpinfo_ver = ($@ ? 'n/a' : $SNMP::Info::VERSION);

  # TODO: (when we have the capabilities table?)
  #  $stats{waps} = sql_scalar('device',['COUNT(*)'], {"model"=>"AIR%"});

  $schema->txn_do(sub {
    $schema->resultset('Statistics')->update_or_create({
      day => localtime->ymd,

      device_count =>
        $schema->resultset('Device')->count_rs->as_query,
      device_ip_count =>
        $schema->resultset('DeviceIp')->count_rs->as_query,
      device_link_count =>
        $schema->resultset('Virtual::DeviceLinks')
          ->count_rs({'me.left_ip' => {'>', \'me.right_ip'}})->as_query,
      device_port_count =>
        $schema->resultset('DevicePort')->count_rs->as_query,
      device_port_up_count =>
        $schema->resultset('DevicePort')->count_rs({up => 'up'})->as_query,
      ip_table_count =>
        $schema->resultset('NodeIp')->count_rs->as_query,
      ip_active_count =>
        $schema->resultset('NodeIp')->search({-bool => 'active'},
          {columns => 'ip', distinct => 1})->count_rs->as_query,
      node_table_count =>
        $schema->resultset('Node')->count_rs->as_query,
      node_active_count =>
        $schema->resultset('Node')->search({-bool => 'active'},
          {columns => 'mac', distinct => 1})->count_rs->as_query,

      netdisco_ver => pretty_version($App::Netdisco::VERSION, 3),
      snmpinfo_ver => $snmpinfo_ver,
      schema_ver   => $schema->schema_version,
      perl_ver     => pretty_version($], 3),
      pg_ver       =>
        pretty_version($schema->storage->dbh->{pg_server_version}, 2),

    }, { key => 'primary' });
  });

  return job_done("Checked expiry and updated stats");
});

# take perl or pg versions and make pretty
sub pretty_version {
  my ($version, $seglen) = @_;
  return unless $version and $seglen;
  return $version if $version !~ m/^[0-9.]+$/;
  $version =~ s/\.//g;
  $version = (join '.', reverse map {scalar reverse}
    unpack("(A${seglen})*", reverse $version));
  $version =~ s/\.000/.0/g;
  $version =~ s/\.0+([1-9]+)/.$1/g;
  return $version;
}

true;
