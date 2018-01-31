package App::Netdisco::Worker::Plugin::MakeRancidConf;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Path::Class;
use List::Util 'first';
use File::Slurper 'write_text';
use App::Netdisco::Util::Permission 'check_acl_no';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $config = setting('rancid') || {};

  my $domain_suffix = setting('domain_suffix') || '';
  my $delimiter = $config->{delimiter} || ':';
  my $down_age  = $config->{down_age} || '1 day';

  my $rancidhome = $config->{rancid_home}
    || dir($ENV{NETDISCO_HOME}, 'rancid')->stringify;
  mkdir $rancidhome if ! -d $rancidhome;
  return Status->error("cannot create or see rancid home: $rancidhome")
    if ! -d $rancidhome;

  my $devices = schema('netdisco')->resultset('Device')->search(undef, {
    '+columns' => { old =>
      \['age(now(), last_discover) > ?::interval', $down_age] },
  });

  $config->{groups}    ||= [{ default => 'any' }];
  $config->{vendormap} ||= [];

  my $routerdb = {};
  while (my $d = $devices->next) {
    my $name =
      check_acl_no($d, $config->{by_ip}) ? $d->ip : ($d->dns || $d->name);
    $name =~ s/$domain_suffix$//
      if check_acl_no($d, $config->{by_hostname});

    my $vmatch =
      first { check_acl_no($d, (values %$_)[0]) } @{$config->{vendormap}};
    my $vendor = $vmatch
      ? (keys %$vmatch)[0] : $d->vendor;

    my $gmatch =
      first { check_acl_no($d, (values %$_)[0]) } @{$config->{groups}};
    my $group = (keys %$gmatch)[0];

    push @{$routerdb->{$group}},
      (sprintf "%s${delimiter}%s${delimiter}%s", $name, $vendor,
        ($d->get_column('old') ? 'down' : 'up'));
  }

  foreach my $group (keys %$routerdb) {
    mkdir dir($rancidhome, $group)->stringify;
    my $content = join "\n", @{$routerdb->{$group}};
    write_text(file($rancidhome, $group, 'router.db')->stringify, "${content}\n");
  }

  return Status->done('Wrote RANCID configuration.');
});

true;

=head1 NAME

MakeRancidConf - Generate RANCID Configuration

=head1 INTRODUCTION

This worker will generate a RANCID configuration for all devices in Netdisco.

Optionally you can provide configuration to control the output, however the
defaults are sane, and will create one RANCID group called "C<default>" which
contains all devices. Those devices not discovered successfully within the
past day will be marked as "down" for RANCID to skip. Configuration is saved
to the "rancid" subdirectory of Netdisco's home folder.

You could run this worker at 09:05 each day using the following configuration:

 schedule:
   makerancidconf:
     when: '5 9 * * *'

=head1 CONFIGURATION

Here is a complete example of the configuration, which must be called
"C<rancid>". All keys are optional:

 rancid:
   rancid_home:  "$ENV{NETDISCO_HOME}/rancid" # default
   down_age:     '1 day'                      # default
   delimiter:    ':'                          # default
   groups:
     groupname1: 'host_group1_acl'
     groupname2: 'host_group2_acl'
   vendormap:
     vname1:     'host_group3_acl'
     vname2:     'host_group4_acl'
   by_ip:        'host_group5_acl'
   by_hostname:  'host_group6_acl'

Note that the default home for writing files is not "C</var/lib/rancid>" so
you may wish to set this (especially if migrating from the old
C<netdisco-rancid-export> script).

Any values above that are a Host Group ACL will take either a single item or
list of Network Identifiers or Device Properties. See the L<ACL
documentation|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
wiki page for full details. We advise you to use the "C<host_groups>" setting
and then refer to named entries in that, for example:

 host_groups:
   coredevices: '192.0.2.0/24'
   edgedevices: '172.16.0.0/16'
 
 rancid:
   groups:
     core_devices: 'group:coredevices'
     edge_devices: 'group:edgedevices'

=head2 C<rancid_home>

The location to write RANCID Group configuration files into. A subdirectory
for each Group will be created.

=head2 C<down_age>

This should be the same or greater than the interval between regular discover
jobs on your network. Devices which have not been discovered within this time
will be marked as "C<down>" to RANCID.

The format is any time interval known and understood by PostgreSQL, such as at
L<https://www.postgresql.org/docs/8.4/static/functions-datetime.html>.

=head2 C<delimiter>

Set this to the delimiter character if needed to be different from the
default.

=head2 C<groups>

This dictionary maps RANCID Group names with configuration which will match
devices in the Netdisco database.

The left hand side (key) should be the RANCID group name, the right hand side
(value) should be a L<Netdisco
ACL|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
to select devices in the Netdisco database.

=head2 C<vendormap>

If the device Vendor in Netdisco is not the same as the RANCID vendor script,
configure a mapping here.

The left hand side (key) should be the RANCID vendor, the right hand side
(value) should be a L<Netdisco
ACL|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
to select devices in the Netdisco database.

=head2 C<by_ip>

L<Netdisco
ACL|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
to select devices which will be written to the RANCID config as an IP address,
instead of the DNS FQDN or SNMP host name.

=head2 C<by_hostname>

L<Netdisco
ACL|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
to select devices which will have the unqualified host name written to the
RANCID config. This is done simply by stripping the C<domain_suffix>
configuration setting from the device FQDN.

=head1 SEE ALSO

=over 4

=item *

L<http://www.shrubbery.net/rancid/>

=item *

L<https://github.com/ytti/oxidized>

=item *

L<https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>

=back

=cut
