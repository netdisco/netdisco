package App::Netdisco::Worker::Plugin::Contact;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;

register_worker({ phase => 'check' }, sub {
  return Status->error('Missing device (-d).')
    unless defined shift->device;
  return Status->done('Contact is able to run');
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $data) = map {$job->$_} qw/device extra/;

  # update pseudo devices directly in database
  unless ($device->is_pseudo()) {
    # snmp connect using rw community
    my $snmp = App::Netdisco::Transport::SNMP->writer_for($device)
      or return Status->defer("failed to connect to $device to update contact");

    my $rv = $snmp->set_contact($data);

    if (!defined $rv) {
      return Status->error(
        "failed to set contact on $device: ". ($snmp->error || ''));
    }

    # confirm the set happened
    $snmp->clear_cache;
    my $new_data = ($snmp->contact || '');
    if ($new_data ne $data) {
      return Status->error("verify of contact failed on $device: $new_data");
    }
  }

  # update netdisco DB
  $device->update({contact => $data});

  return Status->done("Updated contact on $device to [$data]");
});

true;
