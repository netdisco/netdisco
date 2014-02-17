package App::Netdisco::Web::Report;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

get '/report/*' => require_login sub {
    my ($tag) = splat;

    # used in the report search sidebar to populate select inputs
    my ( $domain_list, $class_list, $ssid_list, $vendor_list );

    if ( $tag eq 'netbios' ) {
        $domain_list = [ schema('netdisco')->resultset('NodeNbt')
                ->get_distinct_col('domain') ];
    }
    elsif ( $tag eq 'moduleinventory' ) {
        $class_list = [ schema('netdisco')->resultset('DeviceModule')
                ->get_distinct_col('class') ];
    }
    elsif ( $tag eq 'portssid' ) {
        $ssid_list = [ schema('netdisco')->resultset('DevicePortSsid')
                ->get_distinct_col('ssid') ];
    }
    elsif ( $tag eq 'nodevendor' ) {
        $vendor_list = [
            schema('netdisco')->resultset('Node')->search(
                {},
                {   join     => 'oui',
                    columns  => ['oui.abbrev'],
                    order_by => 'oui.abbrev',
                    group_by => 'oui.abbrev',
                }
                )->get_column('abbrev')->all
        ];
    }

    # trick the ajax into working as if this were a tabbed page
    params->{tab} = $tag;

    var( nav => 'reports' );
    template 'report',
        {
        report      => setting('_reports')->{$tag},
        domain_list => $domain_list,
        class_list  => $class_list,
        ssid_list   => $ssid_list,
        vendor_list => $vendor_list,
        };
};

true;
