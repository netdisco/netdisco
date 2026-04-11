package App::Netdisco::Web::Health;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

use Try::Tiny;

get '/health' => sub {
  content_type 'application/json';

  my $db_ok = try {
    schema('netdisco')->storage->dbh->ping;
    1;
  } catch { 0 };

  my @backends = try {
    schema('netdisco')->resultset('DeviceSkip')
      ->search({ device => '255.255.255.255' })->hri->all;
  } catch { () };

  my $num_backends = scalar @backends;
  my $tot_workers  = 0;
  $tot_workers += $_->{deferrals} for @backends;

  my $status = $db_ok ? 'ok' : 'degraded';
  status( $db_ok ? 200 : 503 );

  return to_json {
    status   => $status,
    db       => ($db_ok ? 'ok' : 'error'),
    backends => $num_backends,
    workers  => $tot_workers,
  };
};

true;
