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
    my @results = schema('netdisco')->resultset('DeviceVlan')->search(
        { 'me.description' => { '!=', 'NULL' },
          'me.vlan' => { '>' => 0 },
          'ports.vlan' => { '>' => 0 },
        },
        {   join   => { 'ports' => 'vlan' },
            select => [
                'me.vlan',
                'me.description',
                { count => { distinct => 'me.ip' } },
                { count => 'ports.vlan' }
            ],
            as       => [qw/ vlan description dcount pcount /],
            group_by => [qw/ me.vlan me.description /],
        }
    )->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json (\@results);
        template 'ajax/report/vlaninventory.tt', { results => $json },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/vlaninventory_csv.tt', { results => \@results },
            { layout => undef };
    }
};

true;
