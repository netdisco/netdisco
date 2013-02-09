package App::Netdisco::Web::TypeAhead;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

# support typeahead with simple AJAX query for device names
ajax '/ajax/data/device/typeahead' => sub {
    my $q = param('query');
    my $set = schema('netdisco')->resultset('Device')->search_fuzzy($q);

    content_type 'application/json';
    return to_json [map {$_->dns || $_->name || $_->ip} $set->all];
};

true;
