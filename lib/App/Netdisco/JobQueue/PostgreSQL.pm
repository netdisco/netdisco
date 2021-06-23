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
  jq_warm_thrusters
  jq_getsome
  jq_locked
  jq_queued
  jq_lock
  jq_defer
  jq_complete
  jq_log
  jq_userlog
  jq_insert
  jq_delete
/;
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

# given a device, tests if any of the primary acls applies
# returns a list of job actions to be denied/skipped on this host.
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
    $rs->search({
      backend => setting('workers')->{'BACKEND'},
    }, { for => 'update' }, )->update({ actionset => [] });

    my $deferrals = setting('workers')->{'max_deferrals'} - 1;
    $rs->search({
      backend => setting('workers')->{'BACKEND'},
      deferrals => { '>' => $deferrals },
    }, { for => 'update' }, )->update({ deferrals => $deferrals });

    $rs->search({
      backend => setting('workers')->{'BACKEND'},
      actionset => { -value => [] },
      deferrals => 0,
    })->delete;

    $rs->update_or_create({
      backend => setting('workers')->{'BACKEND'},
      device  => $_,
      actionset => $actionset{$_},
    }, { key => 'primary' }) for keys %actionset;
  });

  # fix up the pseudo devices which need layer 3
  # TODO remove this after next release
  schema('netdisco')->txn_do(sub {
    my @hosts = grep { defined }
                map  { schema('netdisco')->resultset('Device')->search_for_device($_->{only}) }
                grep { exists $_->{only} and ref '' eq ref $_->{only} }
                grep { exists $_->{driver} and $_->{driver} eq 'cli' }
                    @{ setting('device_auth') };

    $_->update({ layers => \[q{overlay(layers placing '1' from 6 for 1)}] })
      for @hosts;
  });
}

sub jq_getsome {
  my $num_slots = shift;
  return () unless $num_slots and $num_slots > 0;

  my $jobs = schema('netdisco')->resultset('Admin');
  my @returned = ();

  my $tasty = schema('netdisco')->resultset('Virtual::TastyJobs')
    ->search(undef,{ bind => [
      setting('workers')->{'BACKEND'}, setting('job_prio')->{'high'},
      setting('workers')->{'BACKEND'}, setting('workers')->{'max_deferrals'},
      setting('workers')->{'retry_after'}, $num_slots,
    ]});

  while (my $job = $tasty->next) {
    if ($job->device) {
      # need to handle device discovered since backend daemon started
      # and the skiplist was primed. these should be checked against
      # the various acls and have device_skip entry added if needed,
      # and return false if it should have been skipped.
      my @badactions = _get_denied_actions($job->device);
      if (scalar @badactions) {
        schema('netdisco')->resultset('DeviceSkip')->find_or_create({
          backend => setting('workers')->{'BACKEND'}, device => $job->device,
        },{ key => 'device_skip_pkey' })->add_to_actionset(@badactions);

        # will now not be selected in a future _getsome()
        next if scalar grep {$_ eq $job->action} @badactions;
      }
    }

    # remove any duplicate jobs, incuding possibly this job if there
    # is already an equivalent job running

    # note that the self-removal of a job has an unhelpful log: it is
    # reported as a duplicate of itself! however what's happening is that
    # netdisco has seen another running job with same params (but the query
    # cannot see that ID to use it in the message).

    my %job_properties = (
      action => $job->action,
      port   => $job->port,
      subaction => $job->subaction,
      -or => [
        { device => $job->device },
        ($job->device_key ? ({ device_key => $job->device_key }) : ()),
      ],
    );

    my $gone = $jobs->search({
      status => 'queued',
      -and => [
        %job_properties,
        -or => [{
          job => { '!=' => $job->id },
        },{
          job => $job->id,
          -exists => $jobs->search({
            status => { -like => 'queued-%' },
            started => \[q/> (now() - ?::interval)/, setting('jobs_stale_after')],
            %job_properties,
          })->as_query,
        }],
      ],
    }, {for => 'update'})
        ->update({ status => 'error', log => (sprintf 'duplicate of %s', $job->id) });

    debug sprintf 'getsome: cancelled %s duplicate(s) of job %s', ($gone || 0), $job->id;
    push @returned, App::Netdisco::Backend::Job->new({ $job->get_columns });
  }

  return @returned;
}

sub jq_locked {
  my @returned = ();
  my $rs = schema('netdisco')->resultset('Admin')->search({
    status  => ('queued-'. setting('workers')->{'BACKEND'}),
    started => \[q/> (now() - ?::interval)/, setting('jobs_stale_after')],
  });

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

sub jq_lock {
  my $job = shift;
  my $happy = false;

  # lock db row and update to show job has been picked
  try {
    my $updated = schema('netdisco')->resultset('Admin')
      ->search({ job => $job->id, status => 'queued' }, { for => 'update' })
      ->update({
          status  => ('queued-'. setting('workers')->{'BACKEND'}),
          started => \"now()",
      });

    $happy = true if $updated > 0;
  }
  catch {
    error $_;
  };

  return $happy;
}

sub jq_defer {
  my $job = shift;
  my $happy = false;

  # note this taints all actions on the device. for example if both
  # macsuck and arpnip are allowed, but macsuck fails 10 times, then
  # arpnip (and every other action) will be prevented on the device.

  # seeing as defer is only triggered by an SNMP connect failure, this
  # behaviour seems reasonable, to me (or desirable, perhaps).

  try {
    schema('netdisco')->txn_do(sub {
      if ($job->device) {
        schema('netdisco')->resultset('DeviceSkip')->find_or_create({
          backend => setting('workers')->{'BACKEND'}, device => $job->device,
        },{ key => 'device_skip_pkey' })->increment_deferrals;
      }

      # lock db row and update to show job is available
      schema('netdisco')->resultset('Admin')
        ->find($job->id, {for => 'update'})
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

  # now that SNMP connect failures are deferrals and not errors, any complete
  # status, whether success or failure, indicates an SNMP connect. reset the
  # connection failures counter to forget about occasional connect glitches.

  try {
    schema('netdisco')->txn_do(sub {
      if ($job->device) {
        schema('netdisco')->resultset('DeviceSkip')->find_or_create({
          backend => setting('workers')->{'BACKEND'}, device => $job->device,
        },{ key => 'device_skip_pkey' })->update({ deferrals => 0 });
      }

      schema('netdisco')->resultset('Admin')
        ->find($job->id, {for => 'update'})->update({
          status => $job->status,
          log    => $job->log,
          started  => $job->started,
          finished => $job->finished,
          (($job->action eq 'hook') ? (subaction => $job->subaction) : ()),
          ($job->only_namespace ? (action => ($job->action .'::'. $job->only_namespace)) : ()),
        });
    });
    $happy = true;
  }
  catch {
    # use DDP; p $job;
    error $_;
  };

  return $happy;
}

sub jq_log {
  return schema('netdisco')->resultset('Admin')->search({
    'me.action' => { '-not_like' => 'hook::%' },
    -or => [
      { 'me.log' => undef },
      { 'me.log' => { '-not_like' => 'duplicate of %' } },
    ],
  }, {
    prefetch => 'target',
    order_by => { -desc => [qw/entered device action/] },
    rows     => (setting('jobs_qdepth') || 50),
  })->with_times->hri->all;
}

sub jq_userlog {
  my $user = shift;
  return schema('netdisco')->resultset('Admin')->search({
    username => $user,
    log      => { '-not_like' => 'duplicate of %' },
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
            device     => $_->{device},
            device_key => $_->{device_key},
            port       => $_->{port},
            action     => $_->{action},
            subaction  => ($_->{extra} || $_->{subaction}),
            username   => $_->{username},
            userip     => $_->{userip},
            status     => 'queued',
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
        schema('netdisco')->resultset('DeviceSkip')->delete();
      });
  }
}

true;
