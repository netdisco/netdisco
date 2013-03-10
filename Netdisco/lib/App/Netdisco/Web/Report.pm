package App::Netdisco::Web::Report;

use Dancer ':syntax';

get '/report/*' => sub {
    my ($tag) = splat;

    var(nav => 'reports');
    template 'report', {
      report => setting('reports')->{ $tag },
    };
};

true;
