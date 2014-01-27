package App::Netdisco::Web::Plugin::Report::DeviceDnsMismatch;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Device',
        tag          => 'devicednsmismatch',
        label        => 'Device Name / DNS Mismatches',
        provides_csv => 1,
    }
);

get '/ajax/content/report/devicednsmismatch' => require_login sub {
    
    my $suffix = setting('domain_suffix') || '';

    my $rs = schema('netdisco')->resultset('Virtual::DeviceDnsMismatch')
        ->search( undef, { bind => [ $suffix, $suffix ] } );

    return unless $rs->has_rows;

    if ( request->is_ajax ) {
        template 'ajax/report/devicednsmismatch.tt', { results => $rs, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/devicednsmismatch_csv.tt', { results => $rs, },
            { layout => undef };
    }
};

1;
