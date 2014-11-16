package App::Netdisco::JobQueue::PostgreSQL;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Daemon::Job;
use Net::Domain 'hostfqdn';
use Module::Load ();
use Try::Tiny;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  jq_getsome
  jq_getsomep
  jq_locked
  jq_queued
  jq_log
  jq_userlog
  jq_lock
  jq_defer
  jq_complete
  jq_insert
  jq_delete
/;
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

sub _getsome {
  my ($num_slots, $where) = @_;
  return () if ((!defined $num_slots) or ($num_slots < 1));
  return () if ((!defined $where) or (ref {} ne ref $where));

  my $rs = schema('netdisco')->resultset('Admin')
    ->search(
      { status => 'queued', %$where },
      { order_by => 'random()', rows => $num_slots },
    );

  my @returned = ();
  while (my $job = $rs->next) {
      push @returned, App::Netdisco::Daemon::Job->new({ $job->get_columns });
  }
  return @returned;
}

sub jq_getsome {
  return _getsome(shift,
    { action => { -in => setting('job_prio')->{'normal'} } }
  );
}

sub jq_getsomep {
  return _getsome(shift, {
    -or => [{
        username => { '!=' => undef },
        action => { -in => setting('job_prio')->{'normal'} },
      },{
        action => { -in => setting('job_prio')->{'high'} },
    }],
  });
}

sub jq_locked {
  my $fqdn = hostfqdn || 'localhost';
  my @returned = ();

  my $rs = schema('netdisco')->resultset('Admin')
    ->search({status => "queued-$fqdn"});

  while (my $job = $rs->next) {
      push @returned, App::Netdisco::Daemon::Job->new({ $job->get_columns });
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
  return schema('netdisco')->resultset('Admin')->search({}, {
    order_by => { -desc => [qw/entered device action/] },
    rows => 50,
  })->with_times->hri->all;
}

sub jq_userlog {
  my $user = shift;
  return schema('netdisco')->resultset('Admin')->search({
    username => $user,
    finished => { '>' => \"(now() - interval '5 seconds')" },
  })->with_times->hri->all;
}

sub jq_lock {
  my $job = shift;
  my $fqdn = hostfqdn || 'localhost';
  my $happy = false;

  # lock db row and update to show job has been picked
  try {
    schema('netdisco')->txn_do(sub {
      schema('netdisco')->resultset('Admin')
        ->find($job->job, {for => 'update'})
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
  }
  catch {
    error $_;
  };

  return $happy;
}

sub jq_defer {
  my $job = shift;
  my $happy = false;

  try {
    # lock db row and update to show job is available
    schema('netdisco')->txn_do(sub {
      schema('netdisco')->resultset('Admin')
        ->find($job->job, {for => 'update'})
        ->update({ status => 'queued', started => undef });
    });
    $happy = true;
  }
  catch {
    error $_;
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
        ->find($job->job, {for => 'update'})->update({
          status => $job->status,
          log    => $job->log,
          started  => $job->started,
          finished => $job->finished,
        });
    });
    $happy = true;
  }
  catch {
    error $_;
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
  }
  catch {
    error $_;
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
