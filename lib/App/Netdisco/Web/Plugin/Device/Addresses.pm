package App::Netdisco::Web::Plugin::Device::Addresses;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::L3Domain qw/results_span_domains label_rows_by_domain/;

register_device_tab( { tag => 'addresses', label => 'Addresses', provides_csv => 1 } );

# device interface addresses
get '/ajax/content/device/addresses' => require_login sub {
    my $q = param('q');

    my $device
        = schema(vars->{'tenant'})->resultset('Device')->search_for_device($q)
        or send_error( 'Bad device', 400 );

    my @results = $device->device_ips
      ->search( {}, { order_by => 'alias', prefetch => 'device_port' } )
      ->hri->all;

    return unless scalar @results;

    my $multi_domain = results_span_domains(\@results);
    my $rows = label_rows_by_domain(\@results, $multi_domain);

    if (request->is_ajax) {
        my $json = to_json( $rows );
        template 'ajax/device/addresses.tt',
            { results => $json, multi_domain => $multi_domain },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/device/addresses_csv.tt',
            { results => $rows, multi_domain => $multi_domain },
            { layout => undef };
    }
};

1;
