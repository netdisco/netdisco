package App::Netdisco::Worker::Plugin::Discover::Entities;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Permission 'acl_matches';
use Dancer::Plugin::DBIC 'schema';
use String::Util 'trim';
use Encode;

my $clean = sub {
  my $device = shift;

  my $gone = $device->modules->delete;
  debug sprintf ' [%s] modules - removed %d chassis modules',
    $device->ip, $gone;

  $device->modules->update_or_create({
    ip => $device->ip,
    index => 1,
    parent => 0,
    name => 'chassis',
    class => 'chassis',
    pos => -1,
    # too verbose and link doesn't work anyway
    # description => $device->description,
    sw_ver => $device->os_ver,
    serial => $device->serial,
    model => $device->model,
    fru => \'false',
    last_discover => \'LOCALTIMESTAMP',
  });
};

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;

  if (acl_matches($device, 'skip_modules') or not setting('store_modules')) {
      schema('netdisco')->txn_do($clean, $device);
      return Status->info(
        sprintf ' [%s] modules - store_modules is disabled (added one pseudo for chassis)',
        $device->ip);
  }

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");
  my $e_index = $snmp->e_index;

  if (!defined $e_index) {
      schema('netdisco')->txn_do($clean, $device);
      return Status->info(
        sprintf ' [%s] modules - 0 chassis components (added one pseudo for chassis)',
        $device->ip);
  }

  my $e_descr   = $snmp->e_descr;
  my $e_type    = $snmp->e_type;
  my $e_parent  = $snmp->e_parent;
  my $e_name    = $snmp->e_name;
  my $e_class   = $snmp->e_class;
  my $e_pos     = $snmp->e_pos;
  my $e_hwver   = $snmp->e_hwver;
  my $e_fwver   = $snmp->e_fwver;
  my $e_swver   = $snmp->e_swver;
  my $e_model   = $snmp->e_model;
  my $e_serial  = $snmp->e_serial;
  my $e_fru     = $snmp->e_fru;

  # build device modules list for DBIC
  my (@modules, %seen_idx);
  foreach my $entry (keys %$e_index) {
      next unless defined $e_index->{$entry};
      next if $seen_idx{ $e_index->{$entry} }++;

      if ($e_index->{$entry} !~ m/^[0-9]+$/) {
          debug sprintf ' [%s] modules - index %s is not an integer',
            $device->ip, $e_index->{$entry};
          next;
      }

      push @modules, {
          index  => $e_index->{$entry},
          type   => $e_type->{$entry},
          parent => $e_parent->{$entry},
          name   => trim(Encode::decode('UTF-8', $e_name->{$entry})),
          class  => $e_class->{$entry},
          pos    => $e_pos->{$entry},
          hw_ver => trim(Encode::decode('UTF-8', $e_hwver->{$entry})),
          fw_ver => trim(Encode::decode('UTF-8', $e_fwver->{$entry})),
          sw_ver => trim(Encode::decode('UTF-8', $e_swver->{$entry})),
          model  => trim(Encode::decode('UTF-8', $e_model->{$entry})),
          serial => trim(Encode::decode('UTF-8', $e_serial->{$entry})),
          fru    => $e_fru->{$entry},
          description => trim(Encode::decode('UTF-8', $e_descr->{$entry})),
          last_discover => \'LOCALTIMESTAMP',
      };
  }

  foreach my $m (@modules){
    if ($m->{parent} and not exists $seen_idx{ $m->{parent} }){
      # Some combined devices like Nexus with FEX or ASR with Satellites can return invalid
      # EntityMIB trees. This workaround relocates entitites with invalid parents to the root 
      # of the tree, so they are at least visible in the Modules tab (see #710)
      
      debug sprintf ' [%s] Entity %s (%s) has invalid parent %s - attaching as root entity instead',
          $device->ip, ($m->{index} || '"unknown index"'), ($m->{name} || '"unknown name"'), $m->{parent};
      $m->{parent} = undef;
    }
  }

  schema('netdisco')->txn_do(sub {
    my $gone = $device->modules->delete;
    debug sprintf ' [%s] modules - removed %d chassis modules',
      $device->ip, $gone;
    $device->modules->populate(\@modules);

    return Status->info(sprintf ' [%s] modules - added %d new chassis modules',
      $device->ip, scalar @modules);
  });
});

true;
