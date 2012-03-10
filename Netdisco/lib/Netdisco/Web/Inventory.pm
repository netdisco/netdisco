package Netdisco::Web::Inventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

get '/inventory' => sub {
    var(nav => 'inventory');
    template 'inventory', {
      models => scalar schema('netdisco')->resultset('Device')->search({},{
        select => [ 'vendor', 'model', { count => 'ip' } ],
        as => [qw/vendor model count/],
        group_by => [qw/vendor model/],
        order_by => [{-asc => 'vendor'}, {-desc => 'count'}, {-asc => 'model'}],
      }),
      releases => scalar schema('netdisco')->resultset('Device')->search({},{
        select => [ 'os', 'os_ver', { count => 'ip' } ],
        as => [qw/os os_ver count/],
        group_by => [qw/os os_ver/],
        order_by => [{-asc => 'os'}, {-desc => 'count'}, {-asc => 'os_ver'}],
      }),
    };
};

true;
