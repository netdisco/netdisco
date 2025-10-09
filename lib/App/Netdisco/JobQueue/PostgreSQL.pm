package App::Netdisco::JobQueue::PostgreSQL;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::Device 'get_denied_actions';
use App::Netdisco::Backend::Job;
use App::Netdisco::DB::ExplicitLocking ':modes';

use JSON::PP ();
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

sub jq_warm_thrusters {
  my $rs = schema(vars->{'tenant'})->resultset('DeviceSkip');

  schema(vars->{'tenant'})->txn_do(sub {
    $rs->search({
      backend => setting('workers')->{'BACKEND'},
    }, { for => 'update' }, )->update({ actionset => [] });

    # on backend restart, allow one retry of all devices which have
    # reached max retry (max_deferrals)
    my $deferrals = setting('workers')->{'max_deferrals'} - 1;
    $rs->search({
      backend => setting('workers')->{'BACKEND'},
      device => { '!=' => '255.255.255.255' },
      deferrals => { '>' => $deferrals },
    }, { for => 'update' }, )->update({ deferrals => $deferrals });

    $rs->search({
      backend => setting('workers')->{'BACKEND'},
      actionset => { -value => [] }, # special syntax for matching empty ARRAY
      deferrals => 0,
    })->delete;

    # also clean out any previous backend hint
    # primeskiplist action will then run to recreate it
    $rs->search({
      backend => setting('workers')->{'BACKEND'},
      device => '255.255.255.255',
      actionset => { -value => [] }, # special syntax for matching empty ARRAY
    })->delete;
  });
}

sub jq_getsome {
  my $num_slots = shift;
  return () unless $num_slots and $num_slots > 0;

  my $jobs = schema(vars->{'tenant'})->resultset('Admin');
  my @returned = ();

  my $tasty = schema(vars->{'tenant'})->resultset('Virtual::TastyJobs')
    ->search(undef,{ bind => [
      setting('workers')->{'BACKEND'}, setting('job_prio')->{'high'},
      setting('workers')->{'BACKEND'}, setting('workers')->{'max_deferrals'},
      setting('workers')->{'retry_after'}, $num_slots,
    ]});

  while (my $job = $tasty->next) {
    if ($job->device
      and not scalar grep {$job->action eq $_} @{ setting('job_targets_prefix') }) {

      # need to handle device discovered since backend daemon started
      # and the skiplist was primed. these should be checked against
      # the various acls and have device_skip entry added if needed,
      # and return false if it should have been skipped.
      my @badactions = get_denied_actions($job->device);
      if (scalar @badactions) {
        schema(vars->{'tenant'})->resultset('DeviceSkip')->txn_do_locked(EXCLUSIVE, sub {
            schema(vars->{'tenant'})->resultset('DeviceSkip')->find_or_create({
              backend => setting('workers')->{'BACKEND'}, device => $job->device,
            },{ key => 'device_skip_pkey' })->add_to_actionset(@badactions);
        });

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
      # never de-duplicate user-submitted jobs
      username => { '=' => undef },
      userip   => { '=' => undef },
    );

    my $gone = $jobs->search({
      status => 'queued',
      -and => [
        %job_properties,
        -or => [{
          job => { '<' => $job->id },
        },{
          job => $job->id,
          -exists => $jobs->search({
            job => { '>' => $job->id },
            status => 'queued',
            backend => { '!=' => undef },
            started => \[q/> (LOCALTIMESTAMP - ?::interval)/, setting('jobs_stale_after')],
            %job_properties,
          })->as_query,
        }],
      ],
    }, { for => 'update' })
        ->update({ status => 'info', log => (sprintf 'duplicate of %s', $job->id) });

    debug sprintf 'getsome: cancelled %s duplicate(s) of job %s', ($gone || 0), $job->id;
    push @returned, App::Netdisco::Backend::Job->new({ $job->get_columns });
  }

  return @returned;
}

sub jq_locked {
  my @returned = ();
  my $rs = schema(vars->{'tenant'})->resultset('Admin')->search({
    status  => 'queued',
    backend => setting('workers')->{'BACKEND'},
    started => \[q/> (LOCALTIMESTAMP - ?::interval)/, setting('jobs_stale_after')],
  });

  while (my $job = $rs->next) {
      push @returned, App::Netdisco::Backend::Job->new({ $job->get_columns });
  }
  return @returned;
}

sub jq_queued {
  my $job_type = shift;

  return schema(vars->{'tenant'})->resultset('Admin')->search({
    device => { '!=' => undef},
    action => $job_type,
    status => 'queued',
  })->get_column('device')->all;
}

sub jq_lock {
  my $job = shift;
  return true unless $job->id;
  my $happy = false;

  # lock db row and update to show job has been picked
  try {
    my $updated = schema(vars->{'tenant'})->resultset('Admin')
      ->search({ job => $job->id, status => 'queued' }, { for => 'update' })
      ->update({
          status  => 'queued',
          backend => setting('workers')->{'BACKEND'},
          started => \"LOCALTIMESTAMP",
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

  # the deferrable_actions setting exists as a workaround to this behaviour
  # should it be needed by any action (that is, per-device action but
  # do not increment deferrals count and simply try to run again).

  try {
    schema(vars->{'tenant'})->resultset('DeviceSkip')->txn_do_locked(EXCLUSIVE, sub {
      if ($job->device
          and not scalar grep { $job->action eq $_ }
                              @{ setting('deferrable_actions') || [] }) {

        schema(vars->{'tenant'})->resultset('DeviceSkip')->find_or_create({
          backend => setting('workers')->{'BACKEND'}, device => $job->device,
        },{ key => 'device_skip_pkey' })->increment_deferrals;
      }

      debug sprintf 'defer: job %s', ($job->id || 'unknown');

      # lock db row and update to show job is available
      schema(vars->{'tenant'})->resultset('Admin')
        ->search({ job => $job->id }, { for => 'update' })
        ->update({
            device => $job->device, # if job had alias this sets to canonical
            status => 'queued',
            backend => undef,
            started => undef,
            log => $job->log,
        });
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
    schema(vars->{'tenant'})->resultset('DeviceSkip')->txn_do_locked(EXCLUSIVE, sub {
      if ($job->device and not $job->is_offline
            and not scalar grep {$job->action eq $_} @{ setting('job_targets_prefix') }) {

        schema(vars->{'tenant'})->resultset('DeviceSkip')->find_or_create({
          backend => setting('workers')->{'BACKEND'}, device => $job->device,
        },{ key => 'device_skip_pkey' })->update({ deferrals => 0 });
      }

      schema(vars->{'tenant'})->resultset('Admin')
        ->search({ job => $job->id }, { for => 'update' })
        ->update({
          status => $job->status,
          log    => (ref($job->log) eq ref('')) ? $job->log : '',
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
  return schema(vars->{'tenant'})->resultset('Admin')->search({
    (param('backend') ? ('me.backend' => param('backend')) : ()),
    (param('action') ? ('me.action' => param('action')) : ()),
    (param('device') ? (
      -or => [
        { 'me.device' => param('device') },
        { 'target.ip' => param('device') },
      ],
    ) : ()),
    (param('username') ? ('me.username' => param('username')) : ()),
    (param('status') ? (
      (param('status') eq 'Running') ? (
      -and => [
        { 'me.backend' => { '!=' => undef } },
        { 'me.status'  => 'queued' },
      ],
      ) : (
      'me.status' => lc(param('status'))
      )
    ) : ()),
    (param('duration') ? (
      -bool => [
        -or => [
          {
            'me.finished' => undef,
            'me.started'  => { '<' => \[q{(CURRENT_TIMESTAMP - ? ::interval)}, param('duration') .' minutes'] },
          },
          -and => [
            { 'me.started'  => { '!=' => undef } },
            { 'me.finished' => { '!=' => undef } },
            \[ q{ (me.finished - me.started) > ? ::interval }, param('duration') .' minutes'],
          ],
        ],
      ],
    ) : ()),
    'me.log' => [
      { '=' => undef },
      { '-not_like' => 'duplicate of %' },
    ],
  }, {
    prefetch => 'target',
    order_by => { -desc => [qw/entered device action/] },
    rows     => (setting('jobs_qdepth') || 50),
  })->with_times->hri->all;
}

sub jq_userlog {
  my $user = shift;
  return schema(vars->{'tenant'})->resultset('Admin')->search({
    username => $user,
    log      => { '-not_like' => 'duplicate of %' },
    finished => { '>' => \"(CURRENT_TIMESTAMP - interval '5 seconds')" },
  })->with_times->all;
}

sub jq_insert {
  my $jobs = shift;
  $jobs = [$jobs] if ref [] ne ref $jobs;

  my $happy = false;
  try {
    schema(vars->{'tenant'})->txn_do(sub {
      if (scalar @$jobs == 1 and defined $jobs->[0]->{device} and
          scalar grep {$_ eq $jobs->[0]->{action}} @{ setting('_inline_actions') || [] }) {

          # bit of a hack for heroku hosting to avoid DB overload
          return true if setting('defanged_admin') ne 'admin';

          my $spec = $jobs->[0];
          my $row = undef;

          if ($spec->{port}) {
              $row = schema(vars->{'tenant'})->resultset('DevicePort')
                                             ->find($spec->{port}, $spec->{device});
              undef $row unless
                scalar grep {('cf_'. $_) eq $spec->{action}}
                            grep {defined}
                            map {$_->{name}}
                            @{ setting('custom_fields')->{device_port} || [] };
          }
          else {
              $row = schema(vars->{'tenant'})->resultset('Device')
                                             ->find($spec->{device});
              undef $row unless
                scalar grep {('cf_'. $_) eq $spec->{action}}
                            grep {defined}
                            map {$_->{name}}
                            @{ setting('custom_fields')->{device} || [] };
          }

          die 'failed to find row for custom field update' unless $row;

          my $coder = JSON::PP->new->utf8(0)->allow_nonref(1)->allow_unknown(1);
          $spec->{subaction} = $coder->encode( $spec->{extra} || $spec->{subaction} );
          $spec->{action} =~ s/^cf_//;
          $row->make_column_dirty('custom_fields');
          $row->update({
            custom_fields => \['jsonb_set(custom_fields, ?, ?)'
                              => (qq{{$spec->{action}}}, $spec->{subaction}) ]
            })->discard_changes();
      }
      else {
          schema(vars->{'tenant'})->resultset('Admin')->populate([
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
      }
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
      schema(vars->{'tenant'})->txn_do(sub {
        schema(vars->{'tenant'})->resultset('Admin')->search({ job => $id })->delete;
      });
  }
  else {
      schema(vars->{'tenant'})->txn_do(sub {
        schema(vars->{'tenant'})->resultset('Admin')
          ->search({ action => { '!=' => 'primeskiplist'} })->delete();
      });
  }
}

true;
