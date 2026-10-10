package App::Netdisco::Worker::Actions;

use strict;
use warnings;

use Dancer qw/:moose :syntax/;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  supported_actions
  supported_stages
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Worker::Actions

=head1 DESCRIPTION

Introspects the configured worker plugins (perl, and python worklets when
enabled) to learn which actions, and which stages of those actions, can be run.
Nothing is loaded, only the config is read, so this is cheap and has no side
effects. The backend uses it to filter the job queue, and C<netdisco-do
--list> prints it.

=head1 EXPORT_OK

=head2 supported_actions

Returns an array reference of distinct lowercase action names.

=head2 supported_stages

Returns a hash reference of action name to a sorted array reference of the
stages (C<action::stage>) which can be run on their own. Only actions having
stages are present.

=cut

my @phases = qw/check early main user store late/;

# yields [ action, stage-or-undef ] for every configured worker
sub _configured_workers {
  my @found;

  my @core_plugins = @{ setting('worker_plugins') || [] };
  my @user_plugins = @{ setting('extra_worker_plugins') || [] };

  foreach my $plugin (@user_plugins, @core_plugins) {
    my $p = $plugin;
    $p =~ s/^X::/+App::NetdiscoX::Worker::Plugin::/;
    $p = 'App::Netdisco::Worker::Plugin::' . $p if $p !~ m/^\+/;
    $p =~ s/^\+//;

    # same parse as register_worker: only the first sub-namespace is the stage
    if ($p =~ m/::Plugin::([^:]+)(?:::([^:]+))?/i) {
      next if lc $1 eq 'internal';
      push @found, [ lc $1, ($2 ? lc $2 : undef) ];
    }
  }

  # an action may exist only as a python worklet ('action.phase...'), which
  # the loader runs, so it has no perl plugin above but must still be supported
  if (setting('enable_python_worklets')) {
    foreach my $setting (qw/python_worker_plugins extra_python_worker_plugins/) {
      my $config = setting($setting);
      next unless $config and ref [] eq ref $config;

      foreach my $entry (@$config) {
        my $worklet = (ref {} eq ref $entry ? (keys %$entry)[0] : $entry);
        next unless $worklet and $worklet =~ m/^([^.]+)\.(?:([^.]+)\.)?/;

        my ($action, $next) = (lc $1, lc($2 || ''));
        my $stage = (($next and not scalar grep {$_ eq $next} @phases) ? $next : undef);
        push @found, [ $action, $stage ];
      }
    }
  }

  return @found;
}

sub supported_actions {
  my @supported;
  foreach my $worker (_configured_workers()) {
    my $action = $worker->[0];
    push @supported, $action unless scalar grep {$_ eq $action} @supported;
  }

  debug 'Backend supports actions: ' . join(', ', @supported);
  return \@supported;
}

sub supported_stages {
  my %stages;
  foreach my $worker (_configured_workers()) {
    my ($action, $stage) = @$worker;
    $stages{$action}->{$stage} = 1 if $stage;
  }

  return { map {($_ => [ sort keys %{ $stages{$_} } ])} keys %stages };
}

1;
