package App::Netdisco::Web::Plugin::Report::PortUtilization;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category => 'Device',
        tag      => 'portutilization',
        label    => 'Port Utilization',
        provides_csv => 1,
    }
);

get '/ajax/content/report/portutilization' => require_login sub {
    return unless schema('netdisco')->resultset('Device')->count;

    my $age_num = param('age_num') || 3;
    my $age_unit = param('age_unit') || 'months';
    my @results = schema('netdisco')->resultset('Virtual::PortUtilization')
      ->search(undef, { bind => [ "$age_num $age_unit", "$age_num $age_unit", "$age_num $age_unit" ] })->hri->all;

    if (request->is_ajax) {
        my $json = to_json (\@results);
        template 'ajax/report/portutilization.tt', { results => $json },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/portutilization_csv.tt', { results => \@results, },
            { layout => undef };
    }
};

1;
