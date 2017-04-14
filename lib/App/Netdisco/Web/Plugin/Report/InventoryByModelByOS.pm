package App::Netdisco::Web::Plugin::Report::InventoryByModelByOS;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category => 'Device',
        tag      => 'inventorybymodelbyos',
        label    => 'Inventory by Model by OS',
        provides_csv => 0,
    }
);

get '/ajax/content/report/inventorybymodelbyos' => require_login sub {
    my @results = schema('netdisco')->resultset('Device')->search(undef, {
      columns => [qw/vendor model os os_ver/],
      select => [ { count => 'os_ver' } ],
      as => [qw/ os_ver_count /],
      group_by => [qw/ vendor model os os_ver /],
      order_by => ['vendor', 'model', { -desc => 'count' }, 'os_ver'],
    })->hri->all;

    template 'ajax/report/inventorybymodelbyos.tt', { results => \@results, },
        { layout => undef };
};

1;
