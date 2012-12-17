package App::Netdisco::Web::Inventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

get '/inventory' => sub {
    my $models = schema('netdisco')->resultset('Device')->get_models();
    my $releases = schema('netdisco')->resultset('Device')->get_releases();

    var(nav => 'inventory');

    template 'inventory', {
      models => $models,
      releases => $releases,
    };
};

true;
