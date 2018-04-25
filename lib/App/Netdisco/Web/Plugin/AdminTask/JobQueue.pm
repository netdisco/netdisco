package App::Netdisco::Web::Plugin::AdminTask::JobQueue;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::JobQueue qw/jq_log jq_delete/;

use utf8;
use Time::Piece;
use Text::CSV_XS 'csv';
use NetAddr::IP::Lite ':lower';

register_admin_task({
  tag => 'jobqueue',
  label => 'Job Queue',
});

ajax '/ajax/control/admin/jobqueue/del' => require_role admin => sub {
    send_error('Missing job', 400) unless param('job');
    jq_delete( param('job') );
};

ajax '/ajax/control/admin/jobqueue/delall' => require_role admin => sub {
    jq_delete();
};

ajax '/ajax/content/admin/jobqueue' => require_role admin => sub {
    my $filter = NetAddr::IP::Lite->new(param('q'));
    my @data = jq_log($filter);

    foreach my $r (@data) {
      $r->{qstat}->{acl}   = [];
      $r->{qstat}->{next}  = [];
      $r->{qstat}->{fails} = [];
      next unless ($r->{status} eq 'queued');

      foreach my $s (@{$r->{skips}}) {
        (my $row = $s) =~ s/(^\(|\)$)//g;
        next unless $row;
        my %skip = @{ [@{csv(in => \$row)}]->[0] };
        next unless scalar keys %skip;
        $skip{actionset} =~ s/(^{|}$)//g;
        $skip{actionset} = [@{ csv(in => \$skip{actionset}) }]->[0] || [];

        if ($skip{deferrals}) {
          unshift @{$r->{qstat}->{fails}}, sprintf '%s connection failure%s from %s',
            $skip{deferrals}, ($skip{deferrals} > 1 ? 's' : ''), $skip{backend};
        }
        else {
          unshift @{$r->{qstat}->{fails}}, sprintf 'No connection failures from %s',
            $skip{backend};
        }

        if (scalar @{$skip{actionset}}
              and scalar grep {$_ eq $r->{action}} @{$skip{actionset}}) {
          $r->{qstat}->{badacl} = true;
          unshift @{$r->{qstat}->{acl}}, sprintf 'Blocked by ACL on %s', $skip{backend};
        }
        else {
          push @{$r->{qstat}->{acl}}, sprintf '✔ on %s', $skip{backend};
        }

        if ($skip{deferrals} >= setting('workers')->{'max_deferrals'}) {
          $r->{qstat}->{last_defer} = true;
          my $after = (localtime($skip{last_defer}) + setting('workers')->{'retry_after'});
          unshift @{$r->{qstat}->{next}}, sprintf 'Will retry after %s on %s',
            $after->cdate, $skip{backend};
        }
        elsif ($skip{deferrals} > 0) {
          $r->{qstat}->{last_defer} = true;
          unshift @{$r->{qstat}->{next}}, sprintf 'Connect failed at %s on %s',
            localtime($skip{last_defer})->cdate, $skip{backend};
        }
        else {
          push @{$r->{qstat}->{next}}, sprintf '✔ on %s', $skip{backend};
        }
      }
    }

    content_type('text/html');
    template 'ajax/admintask/jobqueue.tt', {
      results => \@data,
    }, { layout => undef };
};

true;
