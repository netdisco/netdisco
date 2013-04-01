package App::Netdisco::Daemon::Worker::Poller::Discover;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::SNMP ':all';
use App::Netdisco::Daemon::Worker::Interactive::Util ':all';

use Role::Tiny;
use namespace::clean;

# queue a discover job for all devices known to Netdisco
sub refresh {
  my ($self, $job) = @_;

  my $devices = schema('netdisco')->resultset('Device')->get_column('ip');

  schema('netdisco')->resultset('Admin')->populate([
    map {{
        device => $_,
        action => 'discover',
        status => 'queued',
    }} ($devices->all)
  ]);

  return done("Queued discover job for all devices");
}

sub discover {
  my ($self, $job) = @_;

}

1;
