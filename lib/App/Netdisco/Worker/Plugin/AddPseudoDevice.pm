package App::Netdisco::Worker::Plugin::AddPseudoDevice;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::DNS 'hostname_from_ip';
use App::Netdisco::Util::Statistics 'pretty_version';
use NetAddr::IP::Lite ':lower';

register_worker({ phase => 'check' }, sub {
    my ($job, $workerconf) = @_;
    my $devip = $job->device->ip;
    my $name  = $job->extra;
    my $ports = $job->port;

    return Status->error('Missing or invalid device name (-e).')
      unless $name
      and $name =~ m/^[[:print:]]+$/
      and $name !~ m/[[:space:]]/;

    my $ip = NetAddr::IP::Lite->new($devip);
    return Status->error('Missing or invalid device IP (-d).')
      unless ($ip and $ip->addr ne '0.0.0.0');

    return Status->error('Missing or invalid number of device ports (-p).')
      unless $ports
      and $ports =~ m/^[[:digit:]]+$/;

    return Status->done('Pseudo Devive can be added');
});

register_worker({ phase => 'main' }, sub {
    my ($job, $workerconf) = @_;
    my $devip = $job->device->ip;
    my $name  = $job->extra;
    my $ports = $job->port;

    schema('netdisco')->txn_do(sub {
      my $device = schema('netdisco')->resultset('Device')
        ->create({
          ip => $devip,
          dns => (hostname_from_ip($devip) || ''),
          name => $name,
          vendor => 'netdisco',
          model => 'pseudodevice',
          num_ports => $ports,
          os => 'netdisco',
          os_ver => pretty_version($App::Netdisco::VERSION, 3),
          layers => '00000100',
          last_discover => \'now()',
          is_pseudo => \'true',
        });
      return unless $device;

      $device->ports->populate([
        [qw/port type descr/],
        map {["Port$_", 'other', "Port$_"]} @{[1 .. $ports]},
      ]);

      # device_ip table is used to show whether topo is "broken"
      schema('netdisco')->resultset('DeviceIp')
        ->create({
          ip => $devip,
          alias => $devip,
        });
    });

    return Status->done(
      sprintf "Pseudo Devive %s (%s) added", $devip, $name);
});

true;
