package App::Netdisco::Web::Plugin::Report::SubnetUtilization;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use POSIX qw/strftime/;

register_report({
  category     => 'IP',
  tag          => 'subnets',
  label        => 'Subnet Utilization',
  provides_csv => 1,
  api_endpoint => 1,
  api_parameters => [
    subnet => {
      description => 'IP Prefix to search',
      default => '0.0.0.0/32',
    },
    daterange => {
      description => 'Date range to search',
      default => ('1970-01-01 to '. strftime('%Y-%m-%d', gmtime)),
    },
    age_invert => {
      description => 'Results should NOT be within daterange',
      type => 'boolean',
      default => 'false',
    },
  ],
});

get '/ajax/content/report/subnets' => require_login sub {
    my $subnet = param('subnet') || '0.0.0.0/32';
    my $agenot = param('age_invert') || '0';

    my $daterange = param('daterange')
      || ('1970-01-01 to '. strftime('%Y-%m-%d', gmtime));
    my ( $start, $end ) = $daterange =~ /(\d+-\d+-\d+)/gmx;
    $start = $start . ' 00:00:00';
    $end   = $end . ' 23:59:59';

    my @results = schema('netdisco')->resultset('Virtual::SubnetUtilization')
      ->search(undef,{
        bind => [ $subnet, $start, $end, $start, $subnet, $start, $start ],
      })->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        template 'ajax/report/subnets.tt', { results => \@results };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/subnets_csv.tt', { results => \@results };
    }
};

1;
