package App::Netdisco::Configuration;

use App::Netdisco::Environment;
use App::Netdisco::Util::DeviceAuth ();
use Dancer ':script';

use Path::Class 'dir';
use Net::Domain 'hostdomain';
use File::ShareDir 'dist_dir';
use URI::Based;

BEGIN {
  if (setting('include_paths') and ref [] eq ref setting('include_paths')) {
    # stuff useful locations into @INC
    push @{setting('include_paths')},
         dir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'nd-site-local', 'lib')->stringify
      if (setting('site_local_files'));
    unshift @INC, @{setting('include_paths')};
  }
}

# set up database schema config from simple config vars
if (ref {} eq ref setting('database')) {
    # override from env for docker

    setting('database')->{name} =
      ($ENV{NETDISCO_DB_NAME} || $ENV{NETDISCO_DBNAME} || setting('database')->{name});

    setting('database')->{host} =
      ($ENV{NETDISCO_DB_HOST} || setting('database')->{host});

    setting('database')->{host} .= (';'. $ENV{NETDISCO_DB_PORT})
      if (setting('database')->{host} and $ENV{NETDISCO_DB_PORT});

    setting('database')->{user} =
      ($ENV{NETDISCO_DB_USER} || setting('database')->{user});

    setting('database')->{pass} =
      ($ENV{NETDISCO_DB_PASS} || setting('database')->{pass});

    my $name = setting('database')->{name};
    my $host = setting('database')->{host};
    my $user = setting('database')->{user};
    my $pass = setting('database')->{pass};

    my $dsn = "dbi:Pg:dbname=${name}";
    $dsn .= ";host=${host}" if $host;

    # set up the netdisco schema now we have access to the config
    # but only if it doesn't exist from an earlier config style
    setting('plugins')->{DBIC}->{netdisco} ||= {
        dsn  => $dsn,
        user => $user,
        password => $pass,
        options => {
            AutoCommit => 1,
            RaiseError => 1,
            auto_savepoint => 1,
            pg_enable_utf8 => 1,
        },
        schema_class => 'App::Netdisco::DB',
    };

    foreach my $c (@{setting('external_databases')}) {
        my $schema = delete $c->{tag} or next;
        next if $schema eq 'netdisco';
        setting('plugins')->{DBIC}->{$schema} = $c;
        setting('plugins')->{DBIC}->{$schema}->{schema_class}
          ||= 'App::Netdisco::GenericDB';
    }
}

# always set this
$ENV{DBIC_TRACE_PROFILE} = 'console';

# override from env for docker
config->{'community'} = ($ENV{NETDISCO_RO_COMMUNITY} ?
  [split ',', $ENV{NETDISCO_RO_COMMUNITY}] : config->{'community'});
config->{'community_rw'} = ($ENV{NETDISCO_RW_COMMUNITY} ?
  [split ',', $ENV{NETDISCO_RW_COMMUNITY}] : config->{'community_rw'});

# if snmp_auth and device_auth not set, add defaults to community{_rw}
if ((setting('snmp_auth') and 0 == scalar @{ setting('snmp_auth') })
    and (setting('device_auth') and 0 == scalar @{ setting('device_auth') })) {
  config->{'community'} = [ @{setting('community')}, 'public' ];
  config->{'community_rw'} = [ @{setting('community_rw')}, 'private' ];
}
# fix up device_auth (or create it from old snmp_auth and community settings)
# also imports legacy sshcollector config
config->{'device_auth'}
  = [ App::Netdisco::Util::DeviceAuth::fixup_device_auth() ];

# defaults for workers
setting('workers')->{queue} ||= 'PostgreSQL';
if ($ENV{ND2_SINGLE_WORKER}) {
  setting('workers')->{tasks} = 1;
  delete config->{'schedule'};
}

# force skipped DNS resolution, if unset
setting('dns')->{hosts_file} ||= '/etc/hosts';
setting('dns')->{no} ||= ['fe80::/64','169.254.0.0/16'];

# set max outstanding requests for AnyEvent::DNS
$ENV{'PERL_ANYEVENT_MAX_OUTSTANDING_DNS'}
  = setting('dns')->{max_outstanding} || 50;
$ENV{'PERL_ANYEVENT_HOSTS'} = setting('dns')->{hosts_file};

# load /etc/hosts
setting('dns')->{'ETCHOSTS'} = {};
{
  # AE::DNS::EtcHosts only works for A/AAAA/SRV, but we want PTR.
  # this loads+parses /etc/hosts file using AE. dirty hack.
  use AnyEvent::Socket 'format_address';
  use AnyEvent::DNS::EtcHosts;
  AnyEvent::DNS::EtcHosts::_load_hosts_unless(sub{},AE::cv);
  no AnyEvent::DNS::EtcHosts; # unimport

  setting('dns')->{'ETCHOSTS'}->{$_} =
    [ map { [ $_ ? (format_address $_->[0]) : '' ] }
          @{ $AnyEvent::DNS::EtcHosts::HOSTS{ $_ } } ]
    for keys %AnyEvent::DNS::EtcHosts::HOSTS;
}

# override from env for docker
if ($ENV{NETDISCO_DOMAIN}) {
  if ($ENV{NETDISCO_DOMAIN} eq 'discover') {
    delete $ENV{NETDISCO_DOMAIN};
    if (! setting('domain_suffix')) {
      info 'resolving domain name...';
      config->{'domain_suffix'} = hostdomain;
    }
  }
  else {
    config->{'domain_suffix'} = $ENV{NETDISCO_DOMAIN};
  }
}

# convert domain_suffix from scalar or list to regexp

config->{'domain_suffix'} = [setting('domain_suffix')]
  if ref [] ne ref setting('domain_suffix');

if (scalar @{ setting('domain_suffix') }) {
  my @suffixes = map { (ref qr// eq ref $_) ? $_ : quotemeta }
                    @{ setting('domain_suffix') };
  my $buildref = '(?:'. (join '|', @suffixes) .')$';
  config->{'domain_suffix'} = qr/$buildref/;
}
else {
  config->{'domain_suffix'} = qr//;
}

# support unordered dictionary as if it were a single item list
if (ref {} eq ref setting('device_identity')) {
  config->{'device_identity'} = [ setting('device_identity') ];
}
else { config->{'device_identity'} ||= [] }

# copy devices_no and devices_only into others
foreach my $name (qw/devices_no devices_only
                    discover_no macsuck_no arpnip_no nbtstat_no
                    discover_only macsuck_only arpnip_only nbtstat_only/) {
  config->{$name} ||= [];
  config->{$name} = [setting($name)] if ref [] ne ref setting($name);
}
foreach my $name (qw/discover_no macsuck_no arpnip_no nbtstat_no/) {
  push @{setting($name)}, @{ setting('devices_no') };
}
foreach my $name (qw/discover_only macsuck_only arpnip_only nbtstat_only/) {
  push @{setting($name)}, @{ setting('devices_only') };
}

# legacy config item names

config->{'devport_vlan_limit'} =
  config->{'deviceport_vlan_membership_threshold'}
  if setting('deviceport_vlan_membership_threshold')
     and not setting('devport_vlan_limit');
delete config->{'deviceport_vlan_membership_threshold'};

config->{'schedule'} = config->{'housekeeping'}
  if setting('housekeeping') and not setting('schedule');
delete config->{'housekeeping'};

# used to have separate types of worker
if (exists setting('workers')->{interactives}
    or exists setting('workers')->{pollers}) {

    setting('workers')->{tasks} ||=
      (setting('workers')->{pollers} || 0)
      + (setting('workers')->{interactives} || 0);

    delete setting('workers')->{pollers};
    delete setting('workers')->{interactives};
}

# moved the timeout setting
setting('workers')->{'timeout'} = setting('timeout')
  if defined setting('timeout')
     and !defined setting('workers')->{'timeout'};

# 0 for workers max_deferrals and retry_after is like disabling
# but we need to fake it with special values
setting('workers')->{'max_deferrals'} ||= (2**30);
setting('workers')->{'retry_after'}   ||= '100 years';

# schedule expire used to be called expiry
setting('schedule')->{expire} ||= setting('schedule')->{expiry}
  if setting('schedule') and exists setting('schedule')->{expiry};
delete config->{'schedule'}->{'expiry'} if setting('schedule');

# upgrade reports config from hash to list
if (setting('reports') and ref {} eq ref setting('reports')) {
    config->{'reports'} = [ map {{
        tag => $_,
        %{ setting('reports')->{$_} }
    }} keys %{ setting('reports') } ];
}

# add system_reports onto reports
config->{'reports'} = [ @{setting('system_reports')}, @{setting('reports')} ];

# set swagger ui location
#config->{plugins}->{Swagger}->{ui_dir} =
  #dir(dist_dir('App-Netdisco'), 'share', 'public', 'swagger-ui')->absolute;

# setup helpers for when request->uri_for() isn't available
# (for example when inside swagger_path())
config->{url_base}
  = URI::Based->new((config->{path} eq '/') ? '' : config->{path});
config->{api_base}
  = config->{url_base}->with('/api/v1')->path;

true;
