package App::Netdisco::JobQueue::PostgreSQL;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::Device
  qw/is_discoverable is_macsuckable is_arpnipable/;
use App::Netdisco::Backend::Job;

use Module::Load ();
use Try::Tiny;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  jq_getsome
  jq_getsomep
  jq_locked
  jq_queued
  jq_warm_thrusters
  jq_lock
  jq_defer
  jq_complete
  jq_log
  jq_userlog
  jq_insert
  jq_delete
/;
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

sub _getsome {
  my ($num_slots, $where) = @_;
  return () if ((!defined $num_slots) or ($num_slots < 1));
  return () if ((!defined $where) or (ref {} ne ref $where));

  my $jobs = schema('netdisco')->resultset('Admin');
  my $rs = $jobs->search({
    status => 'queued',
    device => { '-not_in' =>
      $jobs->skipped(setting('workers')->{'BACKEND'},
                     setting('workers')->{'max_deferrals'},
                     setting('workers')->{'retry_after'})
           ->columns('device')->as_query },
    %$where,
  }, { order_by => 'random()', rows => $num_slots });

  my @returned = ();
  while (my $job = $rs->next) {
      push @returned, App::Netdisco::Backend::Job->new({ $job->get_columns });
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
  my @returned = ();
  my $rs = schema('netdisco')->resultset('Admin')
    ->search({ status => ('queued-'. setting('workers')->{'BACKEND'}) });

  while (my $job = $rs->next) {
      push @returned, App::Netdisco::Backend::Job->new({ $job->get_columns });
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

# given a device, tests if any of the primary acls applies
# returns a list of job actions to be denied/skipped on this host.
sub _get_denied_actions {
  my $device = shift;
  my @badactions = ();
  return @badactions unless $device;

  push @badactions, ('discover', @{ setting('job_prio')->{high} })
    if not is_discoverable($device);

  push @badactions, (qw/macsuck nbtstat/)
    if not is_macsuckable($device);

  push @badactions, 'arpnip'
    if not is_arpnipable($device);

  return @badactions;
}

sub jq_warm_thrusters {
  my @devices = schema('netdisco')->resultset('Device')->all;
  my $rs = schema('netdisco')->resultset('DeviceSkip');
  my %actionset = ();

  foreach my $d (@devices) {
    my @badactions = _get_denied_actions($d);
    $actionset{$d->ip} = \@badactions if scalar @badactions;
  }

  schema('netdisco')->txn_do(sub {
    $rs->search({ backend => setting('workers')->{'BACKEND'} })->delete;
    $rs->populate([
      map {{
        backend => setting('workers')->{'BACKEND'},
        device  => $_,
        actionset => $actionset{$_},
      }} keys %actionset
    ]);
  });
}

sub jq_lock {
  my $job = shift;
  my $happy = false;

  if ($job->device) {
    # need to handle device discovered since backend daemon started
    # and the skiplist was primed. these should be checked against
    # the various acls and have device_skip entry added if needed,
    # and return false if it should have been skipped.
    my @badactions = _get_denied_actions($job->device);
    if (scalar @badactions) {
      schema('netdisco')->resultset('DeviceSkip')->find_or_create({
        backend => setting('workers')->{'BACKEND'}, device => $job->device,
      },{ key => 'device_skip_pkey' })->add_to_actionset(@badactions);

      return false if scalar grep {$_ eq $job->action} @badactions;
    }
  }

  # lock db row and update to show job has been picked
  try {
    schema('netdisco')->txn_do(sub {
      schema('netdisco')->resultset('Admin')
        ->search({ job => $job->job }, { for => 'update' })
        ->update({ status => ('queued-'. setting('workers')->{'BACKEND'}) });

      return unless
        schema('netdisco')->resultset('Admin')
          ->count({ job => $job->job,
                    status => ('queued-'. setting('workers')->{'BACKEND'}) });

      # remove any duplicate jobs, needed because we have race conditions
      # when queueing jobs of a type for all devices
      schema('netdisco')->resultset('Admin')->search({
        status    => 'queued',
        device    => $job->device,
        port      => $job->port,
        action    => $job->action,
        subaction => $job->subaction,
      }, {for => 'update'})->delete();

      $happy = true;
    });
  }
  catch {
    error $_;
  };

  return $happy;
}

sub jq_defer {
  my $job = shift;
  my $happy = false;

  # note this taints all actions on the device. for example if both
  # macsuck and arpnip are allowed, but macsuck fails 10 times, then
  # arpnip (and every other action) will be prevented on the device.

  # seeing as defer is only triggered by an SNMP connect failure, this
  # behaviour seems reasonable, to me (or desirable, perhaps).

  try {
    schema('netdisco')->txn_do(sub {
      if ($job->device) {
        schema('netdisco')->resultset('DeviceSkip')->find_or_create({
          backend => setting('workers')->{'BACKEND'}, device => $job->device,
        },{ key => 'device_skip_pkey' })->increment_deferrals;
      }

      # lock db row and update to show job is available
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

  # now that SNMP connect failures are deferrals and not errors, any complete
  # status, whether success or failure, indicates an SNMP connect. reset the
  # connection failures counter to forget oabout occasional connect glitches.

  try {
    schema('netdisco')->txn_do(sub {
      if ($job->device) {
        schema('netdisco')->resultset('DeviceSkip')->find_or_create({
          backend => setting('workers')->{'BACKEND'}, device => $job->device,
        },{ key => 'device_skip_pkey' })->update({ deferrals => 0 });
      }

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

sub jq_log {
  return schema('netdisco')->resultset('Admin')->search({}, {
    prefetch => 'target',
    order_by => { -desc => [qw/entered device action/] },
    rows => 50,
  })->with_times->hri->all;
}

sub jq_userlog {
  my $user = shift;
  return schema('netdisco')->resultset('Admin')->search({
    username => $user,
    finished => { '>' => \"(now() - interval '5 seconds')" },
  })->with_times->all;
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
