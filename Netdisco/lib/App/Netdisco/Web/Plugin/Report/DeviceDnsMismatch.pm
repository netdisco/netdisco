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

    my @results
        = schema('netdisco')->resultset('Virtual::DeviceDnsMismatch')
        ->search( undef, { bind => [ $suffix, $suffix ] } )
        ->columns( [qw/ ip dns name location contact /] )->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/report/devicednsmismatch.tt', { results => $json },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/devicednsmismatch_csv.tt',
            { results => \@results },
            { layout  => undef };
    }
};

1;
