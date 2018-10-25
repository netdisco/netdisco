package App::Netdisco::Web::Plugin::API::Device;

use Dancer ':syntax';

use Dancer::Plugin::Ajax;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::DBIC;

use Dancer::Exception qw(:all);

use App::Netdisco::Web::Plugin;

use App::Netdisco::Web::Plugin::API::Util;

get '/api/device/all' => sub {
    my $devices=schema('netdisco')->resultset('Device')->all;
    return format_data($devices);
};

post '/api/device/discover' => sub {
    my $devices = from_json( request->body );
    ## NOT IMPLEMENTED YET

};

get '/api/device/searchports' => sub {
    my $para = params;
    my $search = {};
    $search = parse_search_params($para);
    my $devices;
    try {
       $devices=schema('netdisco')->resultset('DevicePort')->search($search);
    };
    return format_data($devices);
};

get '/api/device/search' => sub {
    my $para = params;
    my $search = parse_search_params($para);
    my $devices;
    try {
       $devices=schema('netdisco')->resultset('Device')->search($search);
    };
    return format_data($devices);
};

get '/api/device/:device' => sub {
    my $dev = params->{device};
    my $device = schema('netdisco')->resultset('Device')
      ->search_for_device($dev) or send_error('Bad Device', 404);
    return format_data($device);
};

get '/api/device/:device/:method' => sub {
    my $dev = params->{device};
    my $method = params->{method};
    if (! ($method =~ m/[-_a-z]/)) {
        return format_error(400,"Invalid collection $method.");
    }
    try {
        my $device = schema('netdisco')->resultset('Device')->search_for_device($dev);
        my $results = $device->$method;
        return {} if not defined $results;
        return format_data($results);
    } catch {
        my ($exception) = @_;
        if ($exception =~ m/Can\'t call method "$method" on an undefined value/) {
            return format_error(404,"Device not found.");
        }
        return format_error(400,"Invalid collection $method.");
    };

};
get qr{/api/device/(?<ip>.*)/port/(?<port>.*)/(?<method>[-_a-z]+)$} => sub {
    my $param =captures;
    my $method = $$param{method};
    try {
        my $port = schema('netdisco')->resultset('DevicePort')->find({ip=>$$param{ip}, port => $$param{port}});

        my $results = $port->$method;
        return {} if not defined $results;
        return format_data($results);
    } catch {
        my ($exception) = @_;
        if ($exception =~ m/Can\'t call method "$method" on an undefined value/) {
            return format_error(404,"Port not found.");
        }
        return format_error(400, "Invalid collection $method.");
    };
};

get qr{/api/device/(?<ip>.*)/port/(?<port>.*)} => sub {
    my $param =captures;
    my $port;
    try {
        $port = schema('netdisco')->resultset('DevicePort')->find({ip=>$$param{ip}, port => $$param{port}});
        return format_error(404, "Port not found.") if not defined $port;
        return format_data($port);
    } catch {
        return format_error(404, "Port not found.");
    }
};

true;
