package App::Netdisco::Daemon::Queue;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';
use Try::Tiny;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ add_jobs take_jobs reset_jobs /;
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

{
    my $daemon = schema('daemon');

    # deploy local db if not already done
    try {
        $daemon->storage->dbh_do(sub {
          my ($storage, $dbh) = @_;
          $dbh->selectrow_arrayref("SELECT * FROM admin WHERE 0 = 1");
        });
    }
    catch {
        $daemon->txn_do(sub {
          $daemon->storage->disconnect;
          $daemon->deploy;
        });
    };

    $daemon->storage->disconnect;
    if ($daemon->get_db_version < $daemon->schema_version) {
        $daemon->txn_do(sub { $daemon->upgrade });
    }

    # empty local db of any stale queued jobs
    $daemon->resultset('Admin')->delete;
}

sub add_jobs {
  my ($jobs) = @_;
  try { schema('daemon')->resultset('Admin')->populate($jobs) }
  catch { warn "error adding jobs: $_\n" };
}

sub take_jobs {
  my ($wid, $role, $max) = @_;
  my $jobs = [];

  my $rs = schema('daemon')->resultset('Admin')
    ->search({role => $role, status => 'queued'});

  while (my $job = $rs->next) {
      last if scalar $jobs eq $max;

      try {
          schema('daemon')->txn_do(sub {
              my $row = schema('daemon')->resultset('Admin')->find(
                {job => $job->job},
                {for => 'update'}
              );

              if ($row->status eq 'queued') {
                  $row->update({status => 'taken', wid => $wid});
                  push @$jobs, $row->get_columns;
              }
          });
      };
  }

  return $jobs;
}

sub reset_jobs {
  my ($wid) = @_;
  try {
      schema('daemon')->resultset('Admin')
        ->search({wid => $wid})
        ->update({wid => undef, status => 'queued', started => undef});
  }
  catch { warn "error resetting jobs for wid [$wid]: $_\n" };
}

1;
