package App::Netdisco::Web::AdminTask;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use NetAddr::IP qw/:rfc3021 :lower/;
use App::Netdisco::JobQueue 'jq_insert';

sub add_job {
    my ($action, $device, $extra, $port) = @_;

    my $net = NetAddr::IP->new($device);
    return if
      ($device and (!$net or $net->num == 0 or $net->addr eq '0.0.0.0'));

    my @hostlist = $device ? ($net->hostenum) : (undef);
    @hostlist = ($device) if $action eq 'pingsweep';

    my $happy = jq_insert([map {{
      action => $action,
      ($_     ? (device => ($action eq 'pingsweep' ? $_ : $_->addr)) : ()),
      ($port  ? (port   => $port)    : ()),
      ($extra ? (extra  => $extra)   : ()),
      username => session('logged_in_user'),
      userip => scalar eval {request->remote_address},
    }} @hostlist]);

    foreach my $h (@hostlist) {
        next unless defined $h;
        my $msg = ($happy ? "Queued job to $action device \%s"
                          : "Failed to queue job to $action device \%s");

        schema(vars->{'tenant'})->resultset('UserLog')->create({
          username => session('logged_in_user'),
          userip => scalar eval {request->remote_address},
          event => (sprintf $msg, ($action eq 'pingsweep' ? $h : $h->addr)),
          details => ($extra || 'no user log supplied'),
        });
    }

    return $happy;
}

foreach my $action (@{ setting('job_prio')->{high} },
                    @{ setting('job_prio')->{normal} }) {

    next if $action and $action =~ m/^hook::/; # skip hooks

    ajax "/ajax/control/admin/$action" => require_role admin => sub {
        add_job($action, param('device'), param('extra'), param('port'))
          or send_error('Bad device', 400);
    };

    post "/admin/$action" => require_role admin => sub {
        add_job($action, param('device'), param('extra'), param('port'))
          ? redirect uri_for('/admin/jobqueue')->path
          : redirect uri_for('/')->path;
    };
}

post "/admin/discodevs" => require_role admin => sub {
    add_job((param('action') || 'discover'), param('device'), (param('timeout') || param('extra')), param('port'))
      ? redirect uri_for('/admin/jobqueue')->path
      : redirect uri_for('/')->path;
};

ajax qr{/ajax/control/admin/(?:\w+/)?renumber} => 'admin' => sub {
    send_error('Missing device', 400) unless param('device');
    send_error('Missing new IP', 400) unless param('newip');

    my $device = NetAddr::IP->new(param('device'));
    send_error('Bad device', 400)
      if ! $device or $device->addr eq '0.0.0.0';

    my $newip = NetAddr::IP->new(param('newip'));
    send_error('Bad new IP', 400)
      if ! $newip or $newip->addr eq '0.0.0.0';

    my $happy = jq_insert([{
      action => 'renumber',
      device => $device->addr,
      extra  => $newip->addr,
      username => session('logged_in_user'),
      userip => scalar eval {request->remote_address},
    }]);

    my $msg = ($happy ? 'Queued job to renumber device %s to %s'
                      : 'Failed to queue job to renumber device %s to %s');

    schema(vars->{'tenant'})->resultset('UserLog')->create({
      username => session('logged_in_user'),
      userip => scalar eval {request->remote_address},
      event => (sprintf $msg, $device->addr, $newip->addr),
    });

    return $happy;
};

ajax "/ajax/control/admin/snapshot_req" => require_role admin => sub {
    my $device = NetAddr::IP->new(param('device'));
    send_error('Bad device', 400)
      if ! $device or $device->addr eq '0.0.0.0';

    add_job('loadmibs')
      if not schema(vars->{'tenant'})->resultset('SNMPObject')->count();

    # will store for download and for browsing
    add_job('snapshot', $device->addr, undef, 'db') or send_error('Bad device', 400);
};

get "/ajax/content/admin/snapshot_get" => require_role admin => sub {
    my $device = NetAddr::IP->new(param('device'));
    send_error('Bad device', 400)
      if ! $device or $device->addr eq '0.0.0.0';

    my $content = schema(vars->{'tenant'})->resultset('DeviceSnapshot')->find($device->addr)->cache;
    send_file( \$content, content_type => 'text/plain', filename => ($device->addr .'-snapshot.txt') );
};

ajax "/ajax/control/admin/snapshot_del" => require_role setting('defanged_admin') => sub {
    my $device = NetAddr::IP->new(param('device'));
    send_error('Bad device', 400)
      if ! $device or $device->addr eq '0.0.0.0';

    schema(vars->{'tenant'})->resultset('DeviceSnapshot')->find($device->addr)->delete;
    schema(vars->{'tenant'})->resultset('DeviceBrowser')->search({ip => $device->addr})->delete;
};

true;
