package App::Netdisco::Web::AdminTask;

use Dancer ':syntax';

get '/admin/*' => sub {
    my ($tag) = splat;

    if (! var('user')->admin) {
        status(302);
        header(Location => uri_for('/')->path_query());
        return;
    }

    # trick the ajax into working as if this were a tabbed page
    params->{tab} = $tag;

    var(nav => 'admin');
    template 'admintask', {
      task => setting('admin_tasks')->{ $tag },
    };
};

true;
