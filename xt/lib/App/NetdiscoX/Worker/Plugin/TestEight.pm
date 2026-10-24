package App::NetdiscoX::Worker::Plugin::TestEight;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;

# dies with an exception object, as DBIx::Class does
{
  package App::NetdiscoX::Worker::Plugin::TestEight::Error;
  use overload '""' => sub { 'DBI Exception: duplicate key value violates unique constraint "subnets_pkey"' },
    fallback => 1;
  sub new { return bless {}, shift }
}

register_worker({ phase => 'main', driver => 'direct', title => 'dies with an object' }, sub {
  die App::NetdiscoX::Worker::Plugin::TestEight::Error->new;
});

true;
