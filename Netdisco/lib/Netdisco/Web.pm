package Netdisco::Web;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use Socket6 (); # to ensure dependency is met
use HTML::Entities (); # to ensure dependency is met

use Netdisco::Web::AuthN;
use Netdisco::Web::Search;
use Netdisco::Web::Device;

hook 'before_template' => sub {
    my $tokens = shift;
    $tokens->{uri_base} = request->base->path;
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
