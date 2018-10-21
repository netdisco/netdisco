package App::Netdisco::Web::Plugin::API::Node;

use Dancer ':syntax';

use Dancer::Plugin::Ajax;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::DBIC;

use App::Netdisco::Web::Plugin;

sub api_array_json {
    my $items = shift;
    my @results;
    foreach my $item (@{$items}) {
        my $c = {};
        my $columns = $item->{_column_data};
        foreach my $col (keys %{$columns}) {
            $c->{$col} = $columns->{$col};
        }
        push @results, $c;
    }
    return (\@results);
};

ajax '/api/node/search' => require_login sub {
    my $para = params;
    my $search = {};
    # Generate a hashref of search terms. 
    foreach my $param (keys %{$para}) {
        if ($param ne 'return_url') {
            $search->{$param} = $para->{$param};
        }
    }
    my @ips;
    try {
       @ips = schema('netdisco')->resultset('Node')->search($search);
    };
    return api_array_json(\@ips);
};

ajax '/api/node/:node/:method' => require_login sub {
    my $node = params->{node};
    my $method = params->{method};
    # Make sure $node is actually a mac address in the proper format.
    # TODO change to NetAddr::MAC
    if (!($node =~ m/([0-9a-f]{2}:){5}([0-9a-f]{2})/)){
        status 400;
        return ({ error => "Not a MAC Address. Address must follow the format aa:bb:cc:dd:ee:ff." });
    }
    try {
        my @nodesearch = schema('netdisco')->resultset('Node')->search({ mac => $node});
        # Searching by mac there should be only one result
        my $node = $nodesearch[0]->$method;

        # ResultSets need to be converted to an array of hashes before being returned.
        # Dancer's JSON serializer doesn't like the objects
        if (ref($node) =~ m/ResultSet/) {
            my @nodes = $node->all;
            return api_array_json(\@nodes);
        }
        else {
            my $nodes = $node;
            return $nodes->{_column_data};
        }
    } catch {
        my ($exception) = @_;
        if ($exception =~ m/Can\'t call method "$method" on an undefined value/) {
            status 404;
            return ({ error => "MAC Address not found."});
        }
        status 400;
        return ({ error => "Invalid collection $method." });
    };
};

true;
