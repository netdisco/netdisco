package App::Netdisco::Web::Plugin::API::NodeIP;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Swagger;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::API ':all';

use NetAddr::IP::Lite;

swagger_path {
  description => 'Search for a Node to IP mapping (v4 ARP or v6 Neighbor entry)',
  tags => ['NodeIPs'],
  parameters => [
    resultsource_to_openapi_params('NodeIp'),
    partial => {
      type => 'boolean',
      description => 'Parameters can match anywhere in the value, ignoring case',
    },
  ],
  responses => {
    default => { description => 'A row from the node_ip table' },
  },
},
get '/api/nodeip/search' => require_role api => sub {
    my $para = params;
    my $search = parse_search_params($para);
    my $ips;
    try {
       $ips = schema('netdisco')->resultset('NodeIp')->search($search);
    };
    return format_data($ips);
};

# FIXME does not work as you can have more than one IP entry in that table
# will issue a warning from DBIC
get '/api/nodeip/:node' => sub {
    my $node = params->{node};
    if (defined NetAddr::IP::Lite->new($node)){
        try {
            my $node = schema('netdisco')->resultset('NodeIp')->find({ ip => $node});
            return format_error(404, "IP address not found.")
                if not defined $node->{_column_data};
            return format_data($node);
        };
    }
    else {
        format_error(400,"Not an IP address.");
    }
};

# FIXME does not work as you can have more than one IP entry in that table
# will issue a warning from DBIC
get '/api/nodeip/:node/:method' => sub {
    my $node = params->{node};
    my $method = params->{method};

    if (! ($method =~ m/[-_a-z]/)) {
        return format_error(400,"Invalid collection $method.");
    }

    if (defined NetAddr::IP::Lite->new($node)){
        try {
            my $node = schema('netdisco')->resultset('NodeIp')->find({ ip => $node});

            return format_error(404, "IP address not found.")
                if not defined $node->{_column_data};

            my $data = $node->$method;

            return format_data($data);
        } catch {
            my ($exception) = @_;
            if ($exception =~ m/Can\'t call method "$method" on an undefined value/) {
                return format_error(404, "IP address not found.")
            }
            format_error(400,"Invalid collection $method.");
        };
    }
    else {
        format_error(400,"Not an IP address.");
    }

};
