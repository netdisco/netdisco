package App::Netdisco::Worker::Plugin::MakeRancidConf;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Path::Class;
use List::Util qw/pairkeys pairfirst/;
use File::Slurper qw/read_lines write_text/;
use App::Netdisco::Util::Permission 'check_acl_no';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $config = setting('rancid') || {};

  my $domain_suffix = setting('domain_suffix') || '';
  my $delimiter = $config->{delimiter} || ';';
  my $down_age  = $config->{down_age} || '1 day';
  my $default_group = $config->{default_group} || 'default';

  my $rancidconf = $config->{rancid_conf} || '/etc/rancid';
  my $rancidcvsroot = $config->{rancid_cvsroot}
    || dir($ENV{NETDISCO_HOME}, 'rancid')->stringify;
  mkdir $rancidcvsroot if ! -d $rancidcvsroot;
  return Status->error("cannot create or access rancid cvsroot: $rancidcvsroot")
    if ! -d $rancidcvsroot;

  my $allowed_types = {};
  foreach my $type (qw/base conf/) {
    my $type_file = file($rancidconf, "rancid.types.$type")->stringify;
    debug sprintf("trying rancid configuration file %s\n", $type_file);
    next unless -f $type_file;
    my @lines = read_lines($type_file);
    foreach my $line (@lines) {
      next if $line =~ m/^(?:\#|\$)/;
      $allowed_types->{$1} += 1 if $line =~ m/^([a-z0-9_\-]+);login;.*$/;
    }
  }
  
  return Status->error("You didn't have any device types configured in your rancid installation.")
    if ! scalar keys %$allowed_types;

  my $devices = schema('netdisco')->resultset('Device')->search(undef, {
    '+columns' => { old =>
      \['age(now(), last_discover) > ?::interval', $down_age] },
  });

  $config->{groups}    ||= { default => 'any' };
  $config->{vendormap} ||= {};
  $config->{excluded}  ||= {};
  $config->{by_ip}       ||= {};
  $config->{by_hostname} ||= {};

  my $routerdb = {};
  while (my $d = $devices->next) {

    if (check_acl_no($d, $config->{excluded})) {
      debug " skipping $d: device excluded of export";
      next 
    }

    my $name = check_acl_no($d, $config->{by_ip}) ? $d->ip : ($d->dns || $d->name);
    $name =~ s/$domain_suffix$// if check_acl_no($d, $config->{by_hostname});

    my ($group) =
      (pairkeys pairfirst { check_acl_no($d, $b) } %{ $config->{groups} }) || $default_group;

    my ($vendor) =
      (pairkeys pairfirst { check_acl_no($d, $b) } %{ $config->{vendormap} })
        || $d->vendor;

    if (not ($name and $vendor)) {
      debug " skipping $d: the name or vendor is not defined";
      next
    } elsif ($vendor =~ m/(?:enterprises\.|netdisco)/) {
      debug " skipping $d with unresolved vendor: $vendor";
      next;
    } elsif (scalar keys %$allowed_types and !exists($allowed_types->{$vendor})) {
      debug " skipping $d: $vendor doesn't exist in rancid's vendor list";
      next;
    }

    push @{$routerdb->{$group}},
      (sprintf "%s${delimiter}%s${delimiter}%s", $name, $vendor,
        ($d->get_column('old') ? 'down' : 'up'));
  }

  foreach my $group (keys %$routerdb) {
    mkdir dir($rancidcvsroot, $group)->stringify;
    my $content = "#\n# Router list file for rancid group $group.\n";
    $content .= "# Generate automatically by App::Netdisco::Worker::Plugin::MakeRancidConf\n#\n";
    $content .= join "\n", sort @{$routerdb->{$group}};
    write_text(file($rancidcvsroot, $group, 'router.db')->stringify, "${content}\n");
  }

  return Status->done('Wrote rancid configuration.');
});

true;

=encoding utf8

=head1 NAME

MakeRancidConf - Generate rancid Configuration

=head1 INTRODUCTION

This worker will generate a rancid configuration for all devices in Netdisco.

Optionally you can provide configuration to control the output, however the
defaults are sane for rancid versions 3.x and will create one rancid group
called C<default> which contains all devices. Those devices not discovered
successfully within the past day will be marked as C<down> for rancid to skip.
Configuration is saved to the F<~/rancid> subdirectory of Netdisco's home folder.

Note that this only generates the router.db files, you will still need to
configure rancid's F<.cloginrc> and schedule C<rancid-run> to run.

You could run this worker at 09:05 each day using the following configuration:

 schedule:
   makerancidconf:
     when: '5 9 * * *'

Since MakeRancidConf is a worker module it can also be run via C<netdisco-do>:

 netdisco-do makerancidconf

=head1 CONFIGURATION

Here is a complete example of the configuration, which must be called
C<rancid>. All keys are optional:

 rancid:
   rancid_cvsroot:  '$ENV{NETDISCO_HOME}/rancid' # default
   rancid_conf:     '/etc/rancid'                # default
   down_age:        '1 day'                      # default
   delimiter:       ';'                          # default
   default_group:   'default'                    # default 
   excluded:
     excludegroup1: 'host_group1_acl'
     excludegroup2: 'host_group2_acl'
   groups:
     groupname1:    'host_group3_acl'
     groupname2:    'host_group4_acl'
   vendormap:
     vname1:        'host_group5_acl'
     vname2:        'host_group6_acl'
   by_ip:           'host_group7_acl'
   by_hostname:     'host_group8_acl'

Note that the default directory for writing files is not F</var/lib/rancid> so
you may wish to set this in C<rancid_cvsroot>, (especially if migrating from the old
C<netdisco-rancid-export> script).

Any values above that are a host group ACL will take either a single item or
a list of network identifiers or device properties. See the L<ACL
documentation|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
wiki page for full details. We advise you to use the C<host_groups> setting
and then refer to named entries in that, for example:

 host_groups:
   coredevices: '192.0.2.0/24'
   edgedevices: '172.16.0.0/16'
   grp-nxos:    'os:nx-os'

 rancid:
   groups:
     core_devices: 'group:coredevices'
     edge_devices: 'group:edgedevices'
   vendormap:
     cisco-nx:     'group:grp-nxos'
   by_ip:          'any'

Do not forget that rancid also needs configuring when adding a new group,
such as scheduling the group to run, adding it to F<rancid.conf>, setting up the
email config and creating the repository with C<rancid-cvs>.

=head2 C<rancid_conf>

The location where the rancid configuration (F<rancid.types.base> and
F<rancid.types.conf>) is installed. It will be used to check the existance
of device types before exporting the devices to the rancid configuration. if no match
is found the device will not be added to rancid.

=head2 C<rancid_cvsroot>

The location to write rancid group configuration files (F<router.db>) into. A
subdirectory for each group will be created.

=head2 C<down_age>

This should be the same or greater than the interval between regular discover
jobs on your network. Devices which have not been discovered within this time
will be marked as C<down> to rancid.

The format is any time interval known and understood by PostgreSQL, such as at
L<https://www.postgresql.org/docs/10/static/functions-datetime.html>.

=head2 C<delimiter>

Set this to the delimiter character for your F<router.db> entries if needed to
be different from the default, the default is C<;>.

=head2 C<default_group>

Put devices into this group if they do not match any other groups defined.

=head2 C<excluded>

This dictionary defines a list of devices that you do not wish to export to
rancid configuration.

The value should be a L<Netdisco ACL|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
to select devices in the Netdisco database.

=head2 C<groups>

This dictionary maps rancid group names with configuration which will match
devices in the Netdisco database.

The left hand side (key) should be the rancid group name, the right hand side
(value) should be a L<Netdisco
ACL|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
to select devices in the Netdisco database.

=head2 C<vendormap>

If the device vendor in Netdisco is not the same as the rancid vendor script or
device type, configure a mapping here.

The left hand side (key) should be the rancid device type, the right hand side
(value) should be a L<Netdisco
ACL|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
to select devices in the Netdisco database.

Note that vendors might have a large array of operating systems which require
different rancid modules. Mapping operating systems to rancid device types is
a good solution to use the correct device type. Example:

 host_groups:
   grp-ciscosb:   'os:ros'

 rancid:
   vendormap:
     cisco-sb:    'group:grp-ciscosb'

=head2 C<by_ip>

L<Netdisco
ACL|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
to select devices which will be written to the rancid config as an IP address,
instead of the DNS FQDN or SNMP hostname.

=head2 C<by_hostname>

L<Netdisco
ACL|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
to select devices which will have the unqualified hostname written to the
rancid config. This is done simply by stripping the C<domain_suffix>
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
