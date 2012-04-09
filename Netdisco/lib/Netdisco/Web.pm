package Netdisco::Web;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use Socket6 (); # to ensure dependency is met
use HTML::Entities (); # to ensure dependency is met

use Netdisco::Web::AuthN;
use Netdisco::Web::Search;
use Netdisco::Web::Device;
use Netdisco::Web::Inventory;

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

# set up query strings which describe default search options.
# these are used in both Device and Search templates
hook 'before_template' => sub {
    var('query_defaults' => { map { ($_ => "tab=$_") } qw/node device/ });

    var('query_defaults')->{node} .= "\&$_=". (param($_) || '')
      for qw/stamps vendor archived partial/;
    var('query_defaults')->{device} .= "\&$_=". (param($_) || '')
      for qw/matchall/;
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
