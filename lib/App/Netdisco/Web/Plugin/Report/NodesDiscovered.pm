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
    }
);

get '/ajax/content/report/nodesdiscovered' => require_login sub {
    my $op = param('matchall') ? '-and' : '-or';

    my @results = schema('netdisco')->resultset('Virtual::NodesDiscovered')
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
        template 'ajax/report/nodesdiscovered.tt', { results => $json },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/nodesdiscovered_csv.tt',
            { results => \@results },
            { layout  => undef };
    }
};

1;
