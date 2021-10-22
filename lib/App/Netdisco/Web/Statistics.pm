package App::Netdisco::Web::Statistics;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

get '/ajax/content/statistics' => require_login sub {

    my $stats = schema('netdisco')->resultset('Statistics')
      ->search(undef, { order_by => { -desc => 'day' }, rows => 1 });

    $stats = ($stats->count ? $stats->first : undef);

    var( nav => 'statistics' );
    template 'ajax/statistics.tt',
        { stats => $stats },
        { layout => 'noop' };
};

true;
