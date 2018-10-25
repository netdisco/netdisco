package App::Netdisco::Web::Plugin::API::NodeIP;

use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;

use Dancer::Plugin::DBIC 'schema';

use Dancer::Exception qw(:all);

use NetAddr::IP::Lite;

use App::Netdisco::Web::Plugin;

use App::Netdisco::Web::Plugin::API::Util;

get '/api/nodeip/search' => sub {
    my $para = params;
    my $search = parse_search_params($para);
    my $ips;
    try {
       $ips = schema('netdisco')->resultset('NodeIp')->search($search);
    };
    return format_data($ips);
};

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
