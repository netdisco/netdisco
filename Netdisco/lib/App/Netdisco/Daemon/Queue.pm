package App::Netdisco::Daemon::Queue;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ add_jobs capacity_for take_jobs reset_jobs /;
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

schema('daemon')->deploy;
my $queue = schema('daemon')->resultset('Admin');

sub add_jobs {
  my ($jobs) = @_;
  $queue->populate($jobs);
}

sub capacity_for {
  my ($action) = @_;

  my $action_map = {
    Interactive => [qw/location contact portcontrol portname vlan power/]
  };

  my $role_map = {
    map {$_ => 'Interactive'} @{ $action_map->{Interactive} }
  };

  my $setting_map = {
    Poller => 'daemon_pollers',
    Interactive => 'daemon_interactives',
  };

  my $role = $role_map->{$action};
  my $setting = $setting_map->{$role};

  my $current = $queue->search({role => $role})->count;

  return ($current < setting($setting));
}

sub take_jobs {
  my ($wid, $role, $max) = @_;
  $max ||= 1;

  # asking for more jobs means the current ones are done
  $queue->search({wid => $wid})->delete;

  my $rs = $queue->search(
    {role => $role, wid => 0},
    {rows => $max},
  );

  return [] if $rs->count == 0;

  my @rows = $rs->all;
  $rs->update({wid => $wid});

  return [ map {{$_->get_columns}} @rows ];
}

sub reset_jobs {
  my ($wid) = @_;
  return unless $wid > 1;
  $queue->search({wid => $wid})
        ->update({wid => 0});
}

1;
