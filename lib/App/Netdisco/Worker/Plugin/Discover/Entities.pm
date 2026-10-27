package App::Netdisco::Worker::Plugin::Discover::Entities;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Permission 'acl_matches';
use Dancer::Plugin::DBIC 'schema';
use String::Util 'trim';
use App::Netdisco::Util::SNMPText 'decode_snmp_text';
use App::Netdisco::Util::SNMP qw/walk_mark incomplete_walks_for incomplete_walk_message
  incomplete_walk_level/;

my $clean = sub {
  my $device = shift;
  my $rs = schema('netdisco')->resultset('DeviceModule');

  $rs->upsert([{
    ip => $device->ip,
    index => 1,
    parent => 0,
    name => 'chassis',
    class => 'chassis',
    pos => -1,
    # cleared so a chassis entity from an earlier full walk leaves no stale values
    type => undef,
    hw_ver => undef,
    fw_ver => undef,
    description => undef,
    sw_ver => $device->os_ver,
    serial => $device->serial,
    model => $device->model,
    fru => 'false',
    last_discover => \'LOCALTIMESTAMP',
  }], { touch => ['last_discover'] });

  my $gone = $rs->remove_unseen({ ip => $device->ip }, [{ index => 1 }]);
  debug sprintf ' [%s] modules - removed %d chassis modules',
    $device->ip, $gone;
};

# a walk that was cut short must not look like an emptied table, so the stored
# rows stand
my $keep_stored = sub {
  my ($device, @incomplete) = @_;
  my $message = incomplete_walk_message($device, 'device_module', @incomplete);
  warning $message;
  my $level = incomplete_walk_level(@incomplete);
  return Status->$level($message);
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
  my $walk_mark = walk_mark($snmp);
  my $e_index = $snmp->e_index;

  # checked before the undef branch, so a cut-short e_index skips instead of
  # wiping the modules to a chassis row
  my @incomplete = incomplete_walks_for($device, $snmp, $walk_mark, 'e_index');
  return $keep_stored->($device, @incomplete) if scalar @incomplete;

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

  @incomplete = incomplete_walks_for($device, $snmp, $walk_mark, qw/
    e_index e_descr e_type e_parent e_name e_class e_pos e_hwver e_fwver
    e_swver e_model e_serial e_fru/);
  return $keep_stored->($device, @incomplete) if scalar @incomplete;

  # build device modules list for DBIC
  my (@modules, %seen_idx);
  foreach my $entry (sort keys %$e_index) {
      next unless defined $e_index->{$entry};
      next if $seen_idx{ $e_index->{$entry} }++;

      if ($e_index->{$entry} !~ m/^[0-9]+$/) {
          debug sprintf ' [%s] modules - index %s is not an integer',
            $device->ip, $e_index->{$entry};
          next;
      }

      push @modules, {
          ip     => $device->ip,
          index  => $e_index->{$entry},
          type   => $e_type->{$entry},
          parent => $e_parent->{$entry},
          name   => trim(decode_snmp_text($e_name->{$entry}, $device, "entity $e_index->{$entry} name")),
          class  => $e_class->{$entry},
          pos    => $e_pos->{$entry},
          hw_ver => trim(decode_snmp_text($e_hwver->{$entry}, $device, "entity $e_index->{$entry} hwver")),
          fw_ver => trim(decode_snmp_text($e_fwver->{$entry}, $device, "entity $e_index->{$entry} fwver")),
          sw_ver => trim(decode_snmp_text($e_swver->{$entry}, $device, "entity $e_index->{$entry} swver")),
          model  => trim(decode_snmp_text($e_model->{$entry}, $device, "entity $e_index->{$entry} model")),
          serial => trim(decode_snmp_text($e_serial->{$entry}, $device, "entity $e_index->{$entry} serial")),
          fru    => $e_fru->{$entry},
          description => trim(decode_snmp_text($e_descr->{$entry}, $device, "entity $e_index->{$entry} descr")),
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
    my $rs = schema('netdisco')->resultset('DeviceModule');
    $rs->upsert(\@modules, { touch => ['last_discover'] });
    my $gone = $rs->remove_unseen({ ip => $device->ip },
      [ map {{ index => $_->{index} }} @modules ]);
    debug sprintf ' [%s] modules - removed %d chassis modules',
      $device->ip, $gone;

    return Status->info(sprintf ' [%s] modules - added %d new chassis modules',
      $device->ip, scalar @modules);
  });
});

true;
