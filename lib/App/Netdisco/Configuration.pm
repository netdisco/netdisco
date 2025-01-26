package App::Netdisco::Configuration;

use App::Netdisco::Environment;
use App::Netdisco::Util::DeviceAuth ();
use Dancer ':script';

use FindBin;
use File::Spec;
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

BEGIN {
  no warnings 'redefine';
  use SNMP;

  # hardware exception on macOS at least when translateObj
  # gets something like '.0.0' passed as arg

  my $orig_translate = *SNMP::translateObj{'CODE'};
  *SNMP::translateObj = sub {
    my $arg = $_[0];
    return undef unless defined $arg and $arg !~ m/^[.0]+$/;
    return $orig_translate->(@_);
  };
}

# set up database schema config from simple config vars
if (ref {} eq ref setting('database')) {
    # override from env for docker

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

    my $portnum = undef;
    if ($host and $host =~ m/([^;]+);(.+)/) {
        $host = $1;
        my $params = $2;
        my @opts = split(/;/, $params);
        foreach my $opt (@opts) {
            if ($opt =~ m/port=(\d+)/) {
                $portnum = $1;
            } else {
                # Unhandled connection option, ignore for now
            }
        }
    }

    # activate environment variables so that "psql" can be called
    # and also used by python worklets to connect (to avoid reparsing config)
    $ENV{PGHOST} = $host if $host;
    $ENV{PGPORT} = $portnum if defined $portnum;
    $ENV{PGDATABASE} = $name;
    $ENV{PGUSER} = $user;
    $ENV{PGPASSWORD} = $pass;
    $ENV{PGCLIENTENCODING} = 'UTF8';

    # set up the netdisco schema now we have access to the config
    # but only if it doesn't exist from an earlier config style
    setting('plugins')->{DBIC}->{'default'} ||= {
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
        next if exists setting('plugins')->{DBIC}->{$schema};
        setting('plugins')->{DBIC}->{$schema} = $c;
        setting('plugins')->{DBIC}->{$schema}->{schema_class}
          ||= 'App::Netdisco::GenericDB';
    }

    foreach my $c (@{setting('tenant_databases')}) {
        my $schema = $c->{tag} or next;
        next if exists setting('plugins')->{DBIC}->{$schema};

        my $name = $c->{name} || $c->{tag};
        my $host = $c->{host};
        my $user = $c->{user};
        my $pass = $c->{pass};

        my $dsn = "dbi:Pg:dbname=${name}";
        $dsn .= ";host=${host}" if $host;

        setting('plugins')->{DBIC}->{$schema} = {
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
    }

    # and support tenancies by setting what the default schema points to
    setting('plugins')->{DBIC}->{'netdisco'}->{'alias'} = 'default';

    # allow override of the default tenancy
    setting('plugins')->{DBIC}->{'default'}
     = setting('plugins')->{DBIC}->{$ENV{NETDISCO_DB_TENANT}}
     if $ENV{NETDISCO_DB_TENANT}
        and $ENV{NETDISCO_DB_TENANT} ne 'netdisco'
        and exists setting('plugins')->{DBIC}->{$ENV{NETDISCO_DB_TENANT}};
}

# always set this
$ENV{DBIC_TRACE_PROFILE} = 'console';

# override from env for docker
config->{'community'} = ($ENV{NETDISCO_RO_COMMUNITY} ?
  [split ',', $ENV{NETDISCO_RO_COMMUNITY}] : config->{'community'});
config->{'community_rw'} = ($ENV{NETDISCO_RW_COMMUNITY} ?
  [split ',', $ENV{NETDISCO_RW_COMMUNITY}] : config->{'community_rw'});

# if snmp_auth and device_auth not set, add defaults to community{_rw}
if ((setting('snmp_auth') and 0 == scalar @{ setting('snmp_auth') })
    and (setting('device_auth') and 0 == scalar @{ setting('device_auth') })) {
  config->{'community'} = [ @{setting('community')}, 'public' ];
  config->{'community_rw'} = [ @{setting('community_rw')}, 'private' ];
}
# fix up device_auth (or create it from old snmp_auth and community settings)
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

# override from env for docker
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

# override SNMP bulkwalk from environment
config->{'bulkwalk_off'} = true
  if (exists $ENV{NETDISCO_SNMP_BULKWALK_OFF} and $ENV{NETDISCO_SNMP_BULKWALK_OFF});

# check user's port_control_reasons

config->{'port_control_reasons'} =
  config->{'port_control_reasons'} || config->{'system_port_control_reasons'};

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

# convert expire_devices from single to dict

if (q{} eq ref setting('expire_devices')) {
  config->{'expire_devices'}
    = { 'group:__ANY__' => setting('expire_devices') };
}

# convert tacacs from single to lists

if (ref {} eq ref setting('tacacs')
  and exists setting('tacacs')->{'key'}) {

  config->{'tacacs'} = [
    Host => setting('tacacs')->{'server'},
    Key  => setting('tacacs')->{'key'} || setting('tacacs')->{'secret'},
    Port => (setting('tacacs')->{'port'} || 'tacacs'),
    Timeout => (setting('tacacs')->{'timeout'} || 15),
  ];
}
elsif (ref [] eq ref setting('tacacs')) {
  my @newservers = ();
  foreach my $server (@{ setting('tacacs') }) {
    push @newservers, [
      Host => $server->{'server'},
      Key  => $server->{'key'} || $server->{'secret'},
      Port => ($server->{'port'} || 'tacacs'),
      Timeout => ($server->{'timeout'} || 15),
    ];
  }
  config->{'tacacs'} = [ @newservers ];
}

# support unordered dictionaries as if they were a single item list

if (ref {} eq ref setting('device_identity')) {
  config->{'device_identity'} = [ setting('device_identity') ];
}
else { config->{'device_identity'} ||= [] }

if (ref {} eq ref setting('macsuck_no_deviceport')) {
  config->{'macsuck_no_deviceports'} = [ setting('macsuck_no_deviceport') ];
}
if (ref {} eq ref setting('macsuck_no_deviceports')) {
  config->{'macsuck_no_deviceports'} = [ setting('macsuck_no_deviceports') ];
}
else { config->{'macsuck_no_deviceports'} ||= [] }

if (ref {} eq ref setting('hide_deviceports')) {
  config->{'hide_deviceports'} = [ setting('hide_deviceports') ];
}
else { config->{'hide_deviceports'} ||= [] }

if (ref {} eq ref setting('ignore_deviceports')) {
  config->{'ignore_deviceports'} = [ setting('ignore_deviceports') ];
}
else { config->{'ignore_deviceports'} ||= [] }

# copy old ignore_* into new settings
if (scalar @{ config->{'ignore_interfaces'} }) {
  config->{'host_groups'}->{'__IGNORE_INTERFACES__'}
    = [ map { ($_ !~ m/^port:/) ? "port:$_" : $_ } @{ config->{'ignore_interfaces'} } ];
}
if (scalar @{ config->{'ignore_interface_types'} }) {
  config->{'host_groups'}->{'__IGNORE_INTERFACE_TYPES__'}
    = [ map { ($_ !~ m/^type:/) ? "type:$_" : $_ } @{ config->{'ignore_interface_types'} } ];
}
if (scalar @{ config->{'ignore_notpresent_types'} }) {
  config->{'host_groups'}->{'__NOTPRESENT_TYPES__'}
    = [ map { ($_ !~ m/^type:/) ? "type:$_" : $_ } @{ config->{'ignore_notpresent_types'} } ];
}

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

# portctl_native_vlan used to be called vlanctl
config->{'portctl_native_vlan'} ||= config->{'vlanctl'};
delete config->{'vlanctl'};

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

# 0 for workers max_deferrals and retry_after is like disabling
# but we need to fake it with special values
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

# add system_reports onto reports
config->{'reports'} = [ @{setting('system_reports')}, @{setting('reports')} ];

# set swagger ui location
#config->{plugins}->{Swagger}->{ui_dir} =
  #dir(dist_dir('App-Netdisco'), 'share', 'public', 'swagger-ui')->absolute;

# setup helpers for when request->uri_for() isn't available
# (for example when inside swagger_path())
config->{url_base}
  = URI::Based->new((config->{path} eq '/') ? '' : config->{path});
config->{api_base}
  = config->{url_base}->with('/api/v1')->path;

# device custom_fields with snmp_object creates a hook
my @new_dcf = ();
my @new_hooks = @{ setting('hooks') };

FindBin::again();
my $me = File::Spec->catfile($FindBin::RealBin, 'netdisco-do');

foreach my $field (@{ setting('custom_fields')->{'device'} }) {
    next unless $field->{'name'};

    if (not exists $field->{'snmp_object'} or not $field->{'snmp_object'}) {
        push @new_dcf, $field;
        next;
    }

    # snmp_object implies JSON content in the field
    $field->{'json_list'} = true;
    # snmp_object implies user should not edit in the web
    $field->{'editable'} = false;

    push @new_hooks, {
        type => 'exec',
        event => 'discover',
        with => {
                            # get JSON format of the snmp_object
            cmd => (sprintf q!%s show -d '[%% ip %%]' -e %s --quiet!
                            # this jq will: promote null to [], promote bare string to ["str"], collapse obj to list
                            .q! | jq -cjM '. // [] | if type=="string" then [.] else . end | [ .[] ] | sort'!
                            # send the JSON output into device custom_field (action inline)
                            .q! | %s %s --enqueue -d '[%% ip %%]' -e '-' --quiet!,
                            $me, $field->{'snmp_object'}, $me, ('cf_'. $field->{'name'})),
        },
        filter => {
            no => $field->{'no'},
            only => $field->{'only'},
        },
    };
    push @new_dcf, $field;
}

config->{'hooks'} = \@new_hooks;
config->{'custom_fields'}->{'device'} = \@new_dcf;

true;
