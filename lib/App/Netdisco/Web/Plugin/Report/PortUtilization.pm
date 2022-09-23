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
        api_endpoint => 1,
        api_parameters => [
          age_num => {
            description => 'Mark as Free if down for (quantity)',
            enum => [1 .. 31],
            default => '3',
          },
          age_unit => {
            description => 'Mark as Free if down for (period)',
            enum => [qw/days weeks months years/],
            default => 'months',
          },
        ],
    }
);

get '/ajax/content/report/portutilization' => require_login sub {
    return unless schema(vars->{'tenant'})->resultset('Device')->count;

    my $age_num = param('age_num') || 3;
    my $age_unit = param('age_unit') || 'months';
    my @results = schema(vars->{'tenant'})->resultset('Virtual::PortUtilization')
      ->search(undef, { bind => [ "$age_num $age_unit", "$age_num $age_unit", "$age_num $age_unit" ] })->hri->all;

    if (request->is_ajax) {
        my $json = to_json (\@results);
        template 'ajax/report/portutilization.tt', { results => $json }, { layout => 'noop' };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/portutilization_csv.tt', { results => \@results, }, { layout => 'noop' };
    }
};

1;
