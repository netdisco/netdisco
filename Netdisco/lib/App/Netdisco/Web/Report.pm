package App::Netdisco::Web::Report;

use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;

get '/report/*' => require_login sub {
    my ($tag) = splat;

    # trick the ajax into working as if this were a tabbed page
    params->{tab} = $tag;

    var(nav => 'reports');
    template 'report', {
      report => setting('_reports')->{ $tag },
    };
};

true;
