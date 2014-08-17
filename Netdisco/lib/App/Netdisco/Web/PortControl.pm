package App::Netdisco::Web::PortControl;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::JobQueue qw/jq_insert jq_userlog/;

ajax '/ajax/portcontrol' => require_role port_control => sub {
    send_error('No device/port/field', 400)
      unless param('device') and (param('port') or param('field'));

    my $log = sprintf 'd:[%s] p:[%s] f:[%s]. a:[%s] v[%s]',
      param('device'), (param('port') || ''), param('field'),
      (param('action') || ''), (param('value') || '');

    my %action_map = (
      'location' => 'location',
      'contact'  => 'contact',
      'c_port'   => 'portcontrol',
      'c_name'   => 'portname',
      'c_pvid'   => 'vlan',
      'c_power'  => 'power',
    );

    my $action = $action_map{ param('field') };
    my $subaction = ($action =~ m/^(?:power|portcontrol)/
      ? (param('action') ."-other")
      : param('value'));

    schema('netdisco')->txn_do(sub {
      if (param('port')) {
          my $a = "$action $subaction";
          $a =~ s/-other$//;
          $a =~ s/^portcontrol/port/;

          schema('netdisco')->resultset('DevicePortLog')->create({
            ip => param('device'),
            port => param('port'),
            action => $a,
            username => session('logged_in_user'),
            userip => request->remote_address,
            reason => (param('reason') || 'other'),
            log => param('log'),
          });
      }

      jq_insert({
        device => param('device'),
        port => param('port'),
        action => $action,
        subaction => $subaction,
        username => session('logged_in_user'),
        userip => request->remote_address,
        log => $log,
      });
    });

    content_type('application/json');
    to_json({});
};

ajax '/ajax/userlog' => require_login sub {
    my @jobs = jq_userlog( session('logged_in_user') );

    my %status = (
      'done' => [
        map  {s/\[\]/&lt;empty&gt;/; $_}
        map  { $_->log }
        grep { $_->status eq 'done' }
        grep { defined }
        @jobs
      ],
      'error' => [
        map  {s/\[\]/&lt;empty&gt;/; $_}
        map  { $_->log }
        grep { $_->status eq 'error' }
        grep { defined }
        @jobs
      ],
    );

    content_type('application/json');
    to_json(\%status);
};

true;
