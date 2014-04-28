package App::Netdisco::Daemon::JobQueue::PostgreSQL;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use Role::Tiny;
use namespace::clean;

sub jobqueue_insert {
  my ($self, $settings) = @_;

  schema('netdisco')->resultset('Admin')->create({
    action => $settings->{action},
    device => $settings->{device},
    port   => $settings->{port},
    subaction => $settings->{extra},
    status => 'queued',
  });
}

sub jobqueue_update {
  my ($self, $settings) = @_;

  schema('netdisco')->resultset('Admin')
    ->find(delete $settings->{id}, {for => 'update'})
    ->update($settings);
}

true;
