package App::Netdisco::Web::Report;

use Dancer ':syntax';

get '/report/*' => sub {
    my ($tag) = splat;

    # trick the ajax into working as if this were a tabbed page
    params->{tab} = $tag;

    var(nav => 'reports');
    template 'report', {
      report => setting('reports')->{ $tag },
    };
};

true;
