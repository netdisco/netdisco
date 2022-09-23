package App::Netdisco::Web::Plugin::Report::NodesDiscovered;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::Web 'sql_match';

register_report(
    {   category     => 'Node',
        tag          => 'nodesdiscovered',
        label        => 'Nodes discovered through LLDP/CDP',
        provides_csv => 1,
        api_endpoint => 1,
        api_parameters => [
          remote_id => {
            description => 'Host Name reported',
          },
          remote_type => {
            description => 'Platform reported',
          },
          aps => {
            description => 'Include Wireless APs in the report',
            type => 'boolean',
            default => 'false',
          },
          phones => {
            description => 'Include IP Phones in the report',
            type => 'boolean',
            default => 'false',
          },
          matchall => {
            description => 'Match all parameters (true) or any (false)',
            type => 'boolean',
            default => 'false',
          },
        ],
    }
);

get '/ajax/content/report/nodesdiscovered' => require_login sub {
    my $op = param('matchall') ? '-and' : '-or';

    my @results = schema(vars->{'tenant'})->resultset('Virtual::NodesDiscovered')
        ->search({
            $op => [
              (param('aps') ?
                ('me.remote_type' => { -ilike => 'AP:%' }) : ()),
              (param('phones') ?
                ('me.remote_type' => { -ilike => '%ip_phone%' }) : ()),
              (param('remote_id') ?
                ('me.remote_id' => { -ilike => scalar sql_match(param('remote_id')) }) : ()),
              (param('remote_type') ? ('-or' => [
                map  {( 'me.remote_type' => { -ilike => scalar sql_match($_) } )}
                grep { $_ }
                     (ref param('remote_type') ? @{param('remote_type')} : param('remote_type'))
                ]) : ()),
            ],
        })
        ->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/report/nodesdiscovered.tt', { results => $json }, { layout => 'noop' };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/nodesdiscovered_csv.tt',
            { results => \@results }, { layout => 'noop' };
    }
};

1;
