package App::Netdisco::Web::Plugin::Report::SubnetUtilization;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report({
  category     => 'IP',
  tag          => 'subnets',
  label        => 'Subnet Utilization',
 provides_csv => 1,
});

get '/ajax/content/report/subnets' => require_login sub {
    my $subnet = param('subnet') || '0.0.0.0/32';
    my $agenot = param('age_invert') || '0';
    my ( $start, $end ) = param('daterange') =~ /(\d+-\d+-\d+)/gmx;

    $start = $start . ' 00:00:00';
    $end   = $end . ' 23:59:59';

    my @results = schema('netdisco')->resultset('Virtual::SubnetUtilization')
      ->search(undef,{
        bind => [ $subnet, $start, $end, $start, $subnet, $start, $start ],
      })->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        template 'ajax/report/subnets.tt', { results => \@results },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/subnets_csv.tt', { results => \@results },
            { layout => undef };
    }
};

1;
