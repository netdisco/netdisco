package App::Netdisco::Web;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;

use Dancer::Plugin::DBIC;

use Socket6 (); # to ensure dependency is met
use HTML::Entities (); # to ensure dependency is met
use URI::QueryParam (); # part of URI, to add helper methods

use App::Netdisco::Web::AuthN;
use App::Netdisco::Web::Search;
use App::Netdisco::Web::Device;
use App::Netdisco::Web::PortControl;
use App::Netdisco::Web::Inventory;

hook 'before_template' => sub {
    my $tokens = shift;

    # allow portable static content
    $tokens->{uri_base} = request->base->path
        if request->base->path ne '/';

    # allow portable dynamic content
    $tokens->{uri_for} = \&uri_for;

    # allow very long lists of ports
    $Template::Directive::WHILE_MAX = 10_000;
};

get '/' => sub {
    template 'index';
};

any qr{.*} => sub {
    var('notfound' => true);
    status 'not_found';
    template 'index';
};

true;
