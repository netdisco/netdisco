package App::Netdisco::Web::Plugin::Inventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_navbar_item({
  tag   => 'inventory',
  path  => '/inventory',
  label => 'Inventory',
});

get '/inventory' => require_login sub {
    my $platforms = schema('netdisco')->resultset('Device')->get_platforms();
    my $releases = schema('netdisco')->resultset('Device')->get_releases();

    var(nav => 'inventory');
    template 'inventory', {
      platforms => [$platforms->hri->all],
      releases => [$releases->hri->all],
    };
};

true;
