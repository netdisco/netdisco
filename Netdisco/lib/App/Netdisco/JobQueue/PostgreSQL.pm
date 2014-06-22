package App::Netdisco::JobQueue::PostgreSQL;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use Net::Domain 'hostfqdn';
use Module::Load ();
use Try::Tiny;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  jq_getsome
  jq_locked
  jq_queued
  jq_log
  jq_userlog
  jq_take
  jq_lock
  jq_defer
  jq_complete
  jq_insert
  jq_delete
/;
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

sub jq_getsome {
  my $num_slots = shift;
  my @returned = ();

  my $rs = schema('netdisco')->resultset('Admin')
    ->search(
      {status => 'queued'},
      {order_by => 'random()', rows => ($num_slots || 1)},
    );

  while (my $job = $rs->next) {
      my $job_type = setting('job_types')->{$job->action} or next;
      push @returned, schema('daemon')->resultset('Admin')
        ->new_result({ $job->get_columns, type => $job_type });
  }
  return @returned;
}

sub jq_locked {
  my $fqdn = hostfqdn || 'localhost';
  my @returned = ();

  my $rs = schema('netdisco')->resultset('Admin')
    ->search({status => "queued-$fqdn"});

  while (my $job = $rs->next) {
      my $job_type = setting('job_types')->{$job->action} or next;
      push @returned, schema('daemon')->resultset('Admin')
        ->new_result({ $job->get_columns, type => $job_type });
  }
  return @returned;
}

sub jq_queued {
  my $job_type = shift;

  return schema('netdisco')->resultset('Admin')->search({
    device => { '!=' => undef},
    action => $job_type,
    status => { -like => 'queued%' },
  })->get_column('device')->all;
}

sub jq_log {
  my @returned = ();

  my $rs = schema('netdisco')->resultset('Admin')->search({}, {
    order_by => { -desc => [qw/entered device action/] },
    rows => 50,
  });

  while (my $job = $rs->next) {
      my $job_type = setting('job_types')->{$job->action} or next;
      push @returned, schema('daemon')->resultset('Admin')
        ->new_result({ $job->get_columns, type => $job_type });
  }
  return @returned;
}

sub jq_userlog {
  my $user = shift;
  my @returned = ();

  my $rs = schema('netdisco')->resultset('Admin')->search({
    username => $user,
    finished => { '>' => \"(now() - interval '5 seconds')" },
  });

  while (my $job = $rs->next) {
      my $job_type = setting('job_types')->{$job->action} or next;
      push @returned, schema('daemon')->resultset('Admin')
        ->new_result({ $job->get_columns, type => $job_type });
  }
  return @returned;
}

# PostgreSQL engine depends on LocalQueue, which is accessed synchronously via
# the main daemon process. This is only used by daemon workers which can use
# MCE ->do() method.
sub jq_take {
  my ($wid, $type) = @_;
  Module::Load::load 'MCE';

  # be polite to SQLite database (that is, local CPU)
  debug "$type ($wid): sleeping now...";
  sleep(1);

  debug "$type ($wid): asking for a job";
  MCE->do('take_jobs', $wid, $type);
}

sub jq_lock {
  my $job = shift;
  my $fqdn = hostfqdn || 'localhost';
  my $happy = false;

  # lock db row and update to show job has been picked
  try {
    schema('netdisco')->txn_do(sub {
      schema('netdisco')->resultset('Admin')
        ->find($job->id, {for => 'update'})
        ->update({ status => "queued-$fqdn" });

      # remove any duplicate jobs, needed because we have race conditions
      # when queueing jobs of a type for all devices
      schema('netdisco')->resultset('Admin')->search({
        status    => 'queued',
        device    => $job->device,
        port      => $job->port,
        action    => $job->action,
        subaction => $job->subaction,
      }, {for => 'update'})->delete();
    });
    $happy = true;
  };

  return $happy;
}

sub jq_defer {
  my $job = shift;
  my $happy = false;

  # lock db row and update to show job is available
  try {
    schema('netdisco')->txn_do(sub {
      schema('netdisco')->resultset('Admin')
        ->find($job->id, {for => 'update'})
        ->update({ status => 'queued', started => undef });
    });
    $happy = true;
  };

  return $happy;
}

sub jq_complete {
  my $job = shift;
  my $happy = false;

  # lock db row and update to show job is done/error
  try {
    schema('netdisco')->txn_do(sub {
      schema('netdisco')->resultset('Admin')
        ->find($job->id, {for => 'update'})->update({
          status => $job->status,
          log    => $job->log,
          started  => $job->started,
          finished => $job->finished,
        });
    });
    $happy = true;
  };

  return $happy;
}

sub jq_insert {
  my $jobs = shift;
  $jobs = [$jobs] if ref [] ne ref $jobs;
  my $happy = false;

  try {
    schema('netdisco')->txn_do(sub {
      schema('netdisco')->resultset('Admin')->populate([
        map {{
            device    => $_->{device},
            port      => $_->{port},
            action    => $_->{action},
            subaction => ($_->{extra} || $_->{subaction}),
            username  => $_->{username},
            userip    => $_->{userip},
            status    => 'queued',
        }} @$jobs
      ]);
    });
    $happy = true;
  };

  return $happy;
}

sub jq_delete {
  my $id = shift;

  if ($id) {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('Admin')->find($id)->delete();
      });
  }
  else {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('Admin')->delete();
      });
  }
}

true;
