package App::Netdisco::Daemon::Queue;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';
use Try::Tiny;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ add_jobs take_jobs reset_jobs /;
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

schema('daemon')->deploy;
my $queue = schema('daemon')->resultset('Admin');

sub add_jobs {
  my ($jobs) = @_;
  $queue->populate($jobs);
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

  $rs->update({wid => $wid});
  return [ map {$_->get_columns} $rs->all ];
}

sub reset_jobs {
  my ($wid) = @_;
  return unless $wid > 1;
  $queue->search({wid => $wid})
        ->update({wid => 0});
}

1;
