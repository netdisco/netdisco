package App::Netdisco::Web::Plugin::Report::VlanInventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'VLAN',
        tag          => 'vlaninventory',
        label        => 'VLAN Inventory',
        provides_csv => 1,
    }
);

get '/ajax/content/report/vlaninventory' => require_login sub {
    my $set = schema('netdisco')->resultset('DeviceVlan')->search(
        { 'me.description' => { '!=', 'NULL' } },
        {   join   => { 'ports' => 'vlan' },
            select => [
                'me.vlan',
                'me.description',
                { count => { distinct => 'ports.ip' } },
                { count => 'ports.vlan' }
            ],
            as       => [qw/ vlan description dcount pcount /],
            group_by => [qw/ me.vlan me.description /],
        }
    );
    return unless $set->has_rows;

    if ( request->is_ajax ) {
        template 'ajax/report/vlaninventory.tt', { results => $set, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/vlaninventory_csv.tt', { results => $set, },
            { layout => undef };
    }
};

true;
