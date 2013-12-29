package App::Netdisco::Daemon::Queue;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ add_jobs capacity_for take_jobs reset_jobs scrub_jobs /;
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

schema('daemon')->deploy;
my $queue = schema('daemon')->resultset('Admin');

sub add_jobs {
  my ($jobs) = @_;
  info sprintf "adding %s jobs to local queue", scalar @$jobs;
  $queue->populate($jobs);
}

sub capacity_for {
  my ($action) = @_;
  debug "checking local capacity for action $action";

  my $action_map = {
    Poller => [qw/discoverall discover arpwalk arpnip macwalk macsuck expiry/],
    Interactive => [qw/location contact portcontrol portname vlan power/],
  };

  my $role_map = {
    (map {$_ => 'Poller'} @{ $action_map->{Poller} }),
    (map {$_ => 'Interactive'} @{ $action_map->{Interactive} })
  };

  my $setting_map = {
    Poller => 'pollers',
    Interactive => 'interactives',
  };

  my $role = $role_map->{$action};
  my $setting = $setting_map->{$role};

  my $current = $queue->search({role => $role})->count;

  return ($current < setting('workers')->{$setting});
}

sub take_jobs {
  my ($wid, $role, $max) = @_;
  $max ||= 1;

  # asking for more jobs means the current ones are done
  debug "removing complete jobs for worker $wid from local queue";
  $queue->search({wid => $wid})->delete;

  debug "searching for $max new jobs for worker $wid (role $role)";
  my $rs = $queue->search(
    {role => $role, wid => 0},
    {rows => $max},
  );

  my @rows = $rs->all;
  return [] if scalar @rows == 0;

  debug sprintf "booking out %s jobs to worker %s", scalar @rows, $wid;
  $rs->update({wid => $wid});

  return [ map {{$_->get_columns}} @rows ];
}

sub reset_jobs {
  my ($wid) = @_;
  debug "resetting jobs owned by worker $wid to be available";
  return unless $wid > 1;
  $queue->search({wid => $wid})
        ->update({wid => 0});
}

sub scrub_jobs {
  my ($wid) = @_;
  debug "deleting jobs owned by worker $wid";
  return unless $wid > 1;
  $queue->search({wid => $wid})->delete;
}

1;
