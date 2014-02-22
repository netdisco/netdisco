package App::Netdisco::Web::Statistics;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

get '/ajax/content/statistics' => require_login sub {

    my $time1   = time;
    my $schema  = schema('netdisco');
    my $devices = $schema->resultset('Device');

    # used only to get the PostgreSQL version
    my $users   = $schema->resultset('User')->search(
        {},
        {   select => [ { version => '' } ],
            as     => [qw/ version /],
        }
    );

    my $device_count      = $devices->count;
    my $device_port_count = $schema->resultset('DevicePort')->count;

    my $device_ip_count = $schema->resultset('DeviceIp')
        ->search( undef, { columns => [qw/ alias /] } )->count;

    my $nodes = $schema->resultset('Node')->search(
        {},
        {   columns  => [qw/mac/],
            distinct => 1
        }
    );

    my $node_count       = $nodes->count;
    my $node_table_count = $schema->resultset('Node')->count;

    my $nodes_ips = $schema->resultset('NodeIp')->search(
        {},
        {   columns  => [qw/ip/],
            distinct => 1
        }
    );
    my $ip_count = $nodes_ips->count;
    my $ip_table_count
        = $schema->resultset('NodeIp')->search( {}, { columns => [qw/ip/] } )
        ->count;
    my $device_links = $schema->resultset('DevicePort')
        ->search( { 'remote_ip' => { '!=', undef } } )->count;
    my $schema_version = $schema->get_db_version;
    my $target_version = $schema->schema_version;

    my $time2        = time;
    my $process_time = $time2 - $time1;

    my $disco_ver  = $App::Netdisco::VERSION;
    my $db_version = $users->next->get_column('version');
    my $dbi_ver    = $DBI::VERSION;
    my $dbdpg_ver  = $DBD::Pg::VERSION;

    eval 'require SNMP::Info';
    my $snmpinfo_ver = ($@ ? 'n/a' : $SNMP::Info::VERSION);

    var( nav => 'statistics' );
    template 'ajax/statistics.tt',
        {
        device_count      => $device_count,
        device_ip_count   => $device_ip_count,
        device_links      => $device_links,
        device_port_count => $device_port_count,
        ip_count          => $ip_count,
        ip_table_count    => $ip_table_count,
        node_count        => $node_count,
        node_table_count  => $node_table_count,
        process_time      => $process_time,
        disco_ver         => $disco_ver,
        db_version        => $db_version,
        dbi_ver           => $dbi_ver,
        dbdpg_ver         => $dbdpg_ver,
        snmpinfo_ver      => $snmpinfo_ver,
        schema_ver        => $schema_version,
        },
        { layout => undef };
};

true;
