package App::Netdisco::Backend::Worker::Poller::Expiry;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use Time::Piece;
use App::Netdisco::Backend::Util ':all';

use Role::Tiny;
use namespace::clean;

# expire devices and nodes according to config
sub expire {
  my ($self, $job) = @_;

  if (setting('expire_devices') and setting('expire_devices') > 0) {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('Device')->search({
          -or => [ 'vendor' => undef, 'vendor' => { '!=' => 'netdisco' }],
          last_discover => \[q/< (now() - ?::interval)/,
              (setting('expire_devices') * 86400)],
        })->delete();
      });
  }

  if (setting('expire_nodes') and setting('expire_nodes') > 0) {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('Node')->search({
          time_last => \[q/< (now() - ?::interval)/,
              (setting('expire_nodes') * 86400)],
        })->delete();
      });
  }

  if (setting('expire_nodes_archive') and setting('expire_nodes_archive') > 0) {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('Node')->search({
          -not_bool => 'active',
          time_last => \[q/< (now() - ?::interval)/,
              (setting('expire_nodes_archive') * 86400)],
        })->delete();
      });
  }

  if (setting('expire_jobs') and setting('expire_jobs') > 0) {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('Admin')->search({
          entered => \[q/< (now() - ?::interval)/,
              (setting('expire_jobs') * 86400)],
        })->delete();
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
      ip_count =>
        $schema->resultset('NodeIp')->search(undef,
          {columns => 'ip', distinct => 1})->count_rs->as_query,
      node_table_count =>
        $schema->resultset('Node')->count_rs->as_query,
      node_count =>
        $schema->resultset('Node')->search(undef,
          {columns => 'mac', distinct => 1})->count_rs->as_query,

      netdisco_ver => $App::Netdisco::VERSION,
      snmpinfo_ver => $snmpinfo_ver,
      schema_ver   => $schema->schema_version,
      perl_ver     => pretty_version($], 3),
      pg_ver       =>
        pretty_version($schema->storage->dbh->{pg_server_version}, 2),

    }, { key => 'primary' });
  });

  return job_done("Checked expiry and updated stats");
}

# take perl or pg versions and make pretty
sub pretty_version {
  my ($version, $seglen) = @_;
  return unless $version and $seglen;
  $version =~ s/\.//g;
  $version = (join '.', reverse map {scalar reverse}
    unpack("(A${seglen})*", reverse $version));
  $version =~ s/\.0+/\./g;
  return $version;
}

# expire nodes for a specific device
sub expirenodes {
  my ($self, $job) = @_;

  return job_error('Missing device') unless $job->device;

  schema('netdisco')->txn_do(sub {
    schema('netdisco')->resultset('Node')->search({
      switch => $job->device->ip,
      ($job->port ? (port => $job->port) : ()),
    })->delete(
      ($job->extra ? () : ({ archive_nodes => 1 }))
    );
  });

  return job_done("Expired nodes for ". $job->device->ip);
}

1;
