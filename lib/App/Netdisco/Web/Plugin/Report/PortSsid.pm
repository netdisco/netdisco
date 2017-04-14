package App::Netdisco::Web::Plugin::Report::PortSsid;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Port',
        tag          => 'portssid',
        label        => 'Port SSID Inventory',
        provides_csv => 1,
    }
);

hook 'before_template' => sub {
    my $tokens = shift;

    return
        unless (
        request->path eq uri_for('/report/portssid')->path
        or index(
            request->path, uri_for('/ajax/content/report/portssid')->path
        ) == 0
        );

    # used in the search sidebar template to set selected items
    foreach my $opt (qw/ssid/) {
        my $p = (
            ref [] eq ref param($opt)
            ? param($opt)
            : ( param($opt) ? [ param($opt) ] : [] )
        );
        $tokens->{"${opt}_lkp"} = { map { $_ => 1 } @$p };
    }
};

get '/ajax/content/report/portssid' => require_login sub {

    my $ssid = param('ssid');

    my $rs = schema('netdisco')->resultset('DevicePortSsid');

    if ( defined $ssid ) {

        $rs = $rs->search(
            { ssid => $ssid },
            {   '+columns' => [
                    qw/ device.dns device.name device.model device.vendor port.port/
                ],
                join     => [qw/ device port /],
                collapse => 1,
            }
        )->order_by( [qw/ port.ip port.port /] )->hri;
    }
    else {
        $rs = $rs->get_ssids->hri;

    }

    my @results = $rs->all;
    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/report/portssid.tt',
            { results => $json, opt => $ssid },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/portssid_csv.tt',
            { results => \@results, opt => $ssid },
            { layout => undef };
    }
};

1;
