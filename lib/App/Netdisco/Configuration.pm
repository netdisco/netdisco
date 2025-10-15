package App::Netdisco::Configuration;

use App::Netdisco::Environment;
use App::Netdisco::Util::DeviceAuth ();
use Dancer ':script';

use FindBin;
use File::Spec;
use Path::Class 'dir';
use Net::Domain 'hostdomain';
use AnyEvent::Loop; # avoid EV
use File::ShareDir 'dist_dir';
use Storable 'dclone';
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
      ($ENV{NETDISCO_DB_NAME} || $ENV{NETDISCO_DBNAME} || $ENV{PGDATABASE} || setting('database')->{name});

    setting('database')->{host} =
      ($ENV{NETDISCO_DB_HOST} || $ENV{PGHOST} || setting('database')->{host});

    my $portnum = ($ENV{NETDISCO_DB_PORT} || $ENV{PGPORT});
    setting('database')->{host} .= (';port='. $portnum)
      if (setting('database')->{host} and $portnum);
    # at one time we required the user to add port=
    setting('database')->{host} =~ s/port=port=/port=/ if $portnum;

    setting('database')->{user} =
      ($ENV{NETDISCO_DB_USER} || $ENV{PGUSER} || setting('database')->{user});

    setting('database')->{pass} =
      ($ENV{NETDISCO_DB_PASS} || $ENV{PGPASSWORD} || setting('database')->{pass});

    my $name = setting('database')->{name};
    my $host = setting('database')->{host};
    my $user = setting('database')->{user};
    my $pass = setting('database')->{pass};

    my $dsn = sprintf 'dbi:Pg:dbname=%s', ($name || '');
    $dsn .= ";host=${host}" if $host;

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

    # activate environment variables so that "psql" can be called
    # and also used by python worklets to connect (to avoid reparsing config)
    # must happen after tenants as this rewrites env if NETDISCO_DB_TENANT in play
    my $default = setting('plugins')->{DBIC}->{'default'};
    if ($default->{dsn} =~ m/dbname=([^;]+)/) {
        $ENV{PGDATABASE} = $1;
    }
    if ($default->{dsn} =~ m/host=([^;]+)/) {
        $ENV{PGHOST} = $1;
    }
    if ($default->{dsn} =~ m/port=(\d+)/) {
        $ENV{PGPORT} = $1;
    }
    $ENV{PGUSER} = $default->{user};
    $ENV{PGPASSWORD} = $default->{password};
    $ENV{PGCLIENTENCODING} = 'UTF8';

    foreach my $c (@{setting('external_databases')}) {
        my $schema = delete $c->{tag} or next;
        next if exists setting('plugins')->{DBIC}->{$schema};
        setting('plugins')->{DBIC}->{$schema} = $c;
        setting('plugins')->{DBIC}->{$schema}->{schema_class}
          ||= 'App::Netdisco::GenericDB';
    }
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
  use AnyEvent::Loop;
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

# for managing database portctl_roles

config->{'portctl_checkpoint'} = {};
config->{'portctl_by_role_shadow'}
  = dclone (setting('portctl_by_role') || {});

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

# rename snmp_field_protection to just be field_protection
config->{'field_protection'} = config->{'snmp_field_protection'}
  if exists config->{'snmp_field_protection'};

# if user has previously configured too_many_devices away from 1000 default,
# then copy it into netmap_performance_limit_max_devices
config->{'netmap_performance_limit_max_devices'} =
  config->{'sidebar_defaults'}->{'device_netmap'}->{'too_many_devices'}->{'default'}
  if config->{'sidebar_defaults'}->{'device_netmap'}->{'too_many_devices'}->{'default'}
    and config->{'sidebar_defaults'}->{'device_netmap'}->{'too_many_devices'}->{'default'} != 1000;
delete config->{'sidebar_defaults'}->{'device_netmap'}->{'too_many_devices'};

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

# upgrade bare bind_params to dict
foreach my $r ( @{setting('reports')} ) {
    next unless exists $r->{bind_params};
    my $new_bind_params = [ map {ref $_ ? $_ : {param => $_}} @{ $r->{bind_params} } ];
    $r->{'bind_params'} = $new_bind_params;
}

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
            cmd => (sprintf q![%% ndo %%] show -d '[%% ip %%]' -e %s --quiet!
                            # this jq will: promote null to [], promote bare string to ["str"], collapse obj to list
                            .q! | jq -cjM '. // [] | if type=="string" then [.] else . end | [ .[] ] | sort'!
                            # send the JSON output into device custom_field (action inline)
                            .q! | [%% ndo %%] %s --enqueue -d '[%% ip %%]' -e '@-' --quiet!,
                            $field->{'snmp_object'}, ('cf_'. $field->{'name'})),
        },
        filter => {
            no => $field->{'no'},
            only => $field->{'only'},
        },
    };
    push @new_dcf, $field;
}

# #1040 change with-nodes to be job hook
foreach my $action (qw(macsuck arpnip)) {
    push @new_hooks, {
        type => 'exec',
        event => 'new_device',
        with => {
            cmd => (sprintf q![%% ndo %%] %s --enqueue -d '[%% ip %%]' --quiet!, $action)
        }
    };
}

config->{'hooks'} = \@new_hooks;
config->{'custom_fields'}->{'device'} = \@new_dcf;

true;
