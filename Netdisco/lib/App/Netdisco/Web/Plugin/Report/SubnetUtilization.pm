package App::Netdisco::Web::Plugin::Report::SubnetUtilization;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::Web (); # for interval_to_daterange

register_report({
  category     => 'IP',
  tag          => 'subnets',
  label        => 'Subnet Utilization',
 provides_csv => 1,
});

get '/ajax/content/report/subnets' => require_login sub {
    my $subnet = param('subnet') || '0.0.0.0/32';
    my $age = param('age') || '7 days';
    $age = '7 days' unless $age =~ m/^(?:\d+)\s+(?:day|week|month|year)s?$/;

    my $daterange = App::Netdisco::Util::Web::interval_to_daterange($age);

    my @results = schema('netdisco')->resultset('Virtual::SubnetUtilization')
      ->search(undef,{
        bind => [ $subnet, $age, $age, $subnet, $age, $age ],
      })->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        template 'ajax/report/subnets.tt',
            { results => \@results, daterange => $daterange },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/subnets_csv.tt', { results => \@results },
            { layout => undef };
    }
};

1;
