package App::Netdisco::Web::TypeAhead;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Util::Web (); # for sort_port

ajax '/ajax/data/devicename/typeahead' => require_login sub {
    return '[]' unless setting('navbar_autocomplete');

    my $q = param('query') || param('term');
    my $set = schema('netdisco')->resultset('Device')->search_fuzzy($q);

    content_type 'application/json';
    to_json [map {$_->dns || $_->name || $_->ip} $set->all];
};

ajax '/ajax/data/deviceip/typeahead' => require_login sub {
    my $q = param('query') || param('term');
    my $set = schema('netdisco')->resultset('Device')->search_fuzzy($q);

    my @data = ();
    while (my $d = $set->next) {
        my $label = $d->ip;
        if ($d->dns or $d->name) {
            $label = sprintf '%s (%s)',
              ($d->dns || $d->name), $d->ip;
        }
        push @data, { label => $label, value => $d->ip };
    }

    content_type 'application/json';
    to_json \@data;
};

ajax '/ajax/data/port/typeahead' => require_login sub {
    my $dev  = param('dev1')  || param('dev2');
    my $port = param('port1') || param('port2');
    send_error('Missing device', 400) unless $dev;

    my $device = schema('netdisco')->resultset('Device')
      ->find({ip => $dev});
    send_error('Bad device', 400) unless $device;

    my $set = $device->ports({},{order_by => 'port'});
    $set = $set->search({port => { -ilike => "\%$port\%" }})
      if $port;

    my $results = [
      map  {{ label => (sprintf "%s (%s)", $_->port, $_->name), value => $_->port }}
      sort { &App::Netdisco::Util::Web::sort_port($a->port, $b->port) } $set->all
    ];

    content_type 'application/json';
    to_json \@$results;
};

ajax '/ajax/data/subnet/typeahead' => require_login sub {
    my $q = param('query') || param('term');
    $q = "$q\%" if $q !~ m/\%/;
    my $nets = schema('netdisco')->resultset('Subnet')->search(
           { 'me.net::text'  => { '-ilike' => $q }},
           { columns => ['net'], order_by => 'net' } );

    content_type 'application/json';
    to_json [map {$_->net} $nets->all];
};

true;
