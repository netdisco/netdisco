package App::Netdisco::Web::Report;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

get '/report/*' => require_login sub {
    my ($tag) = splat;

    # used in the report search sidebar to populate select inputs
    my $domain_list
        = [
        schema('netdisco')->resultset('NodeNbt')->get_distinct_col('domain')
        ];

    # trick the ajax into working as if this were a tabbed page
    params->{tab} = $tag;

    var( nav => 'reports' );
    template 'report',
        {
        report      => setting('_reports')->{$tag},
        domain_list => $domain_list,
        };
};

true;
