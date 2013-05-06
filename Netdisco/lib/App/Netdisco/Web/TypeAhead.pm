package App::Netdisco::Web::TypeAhead;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use App::Netdisco::Util::Web (); # for sort_port
use Try::Tiny;

ajax '/ajax/data/devicename/typeahead' => sub {
    my $q = param('query') || param('term');
    my $set = schema('netdisco')->resultset('Device')->search_fuzzy($q);

    content_type 'application/json';
    return to_json [map {$_->dns || $_->name || $_->ip} $set->all];
};

ajax '/ajax/data/deviceip/typeahead' => sub {
    my $q = param('query') || param('term');
    my $set = schema('netdisco')->resultset('Device')->search_fuzzy($q);

    content_type 'application/json';
    return to_json [map {
      {label => ($_->dns || $_->name || $_->ip), value => $_->ip}
    } $set->all];
};

ajax '/ajax/data/port/typeahead' => sub {
    my $dev  = param('dev1')  || param('dev2');
    my $port = param('port1') || param('port2');
    return unless length $dev;

    my $set = undef;
    try {
        $set = schema('netdisco')->resultset('Device')
          ->find({ip => $dev})->ports({},{order_by => 'port'});
        $set = $set->search({port => { -ilike => "\%$port\%" }})
          if length $port;
    };
    return unless defined $set;

    my $results = [ sort { &App::Netdisco::Util::Web::sort_port($a->port, $b->port) } $set->all ];
    return unless scalar @$results;

    content_type 'application/json';
    return to_json [map {$_->port} @$results];
};

true;
