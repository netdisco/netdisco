package App::Netdisco::Daemon::JobQueue::PostgreSQL;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use Net::Domain 'hostfqdn';
use Try::Tiny;

use Role::Tiny;
use namespace::clean;

#jq_get
#jq_getlocal
#jq_queued
#jq_lock
#jq_defer
#jq_complete
#jq_insert

sub jq_get {
  my ($self, $num_slots) = @_;
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

sub jq_getlocal {
  my $self = shift;
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
  my ($self, $job_type) = @_;

  return schema('netdisco')->resultset('Admin')->search({
      device => { '!=' => undef},
      action => $job_type,
      status => { -like => 'queued%' },
  })->get_column('device')->all;
}

sub jq_lock {
  my ($self, $job) = @_;
  my $fqdn = hostfqdn || 'localhost';
  my $happy = 0;

  # lock db row and update to show job has been picked
  try {
    schema('netdisco')->txn_do(sub {
      schema('netdisco')->resultset('Admin')
        ->find($job->id, {for => 'update'})
        ->update({ status => "queued-$fqdn" });
    });
    $happy = 1;
  };

  return $happy;
}

sub jq_defer {
  my ($self, $job) = @_;
  my $happy = 0;

  # lock db row and update to show job is available
  try {
    schema('netdisco')->txn_do(sub {
      schema('netdisco')->resultset('Admin')
        ->find($job->id, {for => 'update'})
        ->update({ status => 'queued' });
    });
    $happy = 1;
  };

  return $happy;
}

sub jq_complete {
  my ($self, $job) = @_;
  my $happy = 0;

  # lock db row and update to show job is done/error
  try {
    schema('netdisco')->txn_do(sub {
      schema('netdisco')->resultset('Admin')
        ->find($job->id, {for => 'update'})->update({
          status => $job->status,
          log    => $job->log,
          finished => $job->finished,
        });
    });
    $happy = 1;
  };

  return $happy;
}

sub jq_insert {
  my ($self, $jobs) = @_;
  $jobs = [$jobs] if ref [] ne ref $jobs;
  my $happy = 0;

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
    $happy = 1;
  };

  return $happy;
}

true;
