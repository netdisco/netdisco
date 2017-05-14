package App::Netdisco::Configuration;

use App::Netdisco::Environment;
use Dancer ':script';

use Path::Class 'dir';

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
    my $name = ($ENV{NETDISCO_DBNAME} || setting('database')->{name} || 'netdisco');
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

# defaults for workers
setting('workers')->{queue} ||= 'PostgreSQL';
if (exists setting('workers')->{interactives}
    or exists setting('workers')->{pollers}) {

    setting('workers')->{tasks} =
      (setting('workers')->{pollers} || 0)
      + (setting('workers')->{interactives} || 0);

    delete setting('workers')->{pollers};
    delete setting('workers')->{interactives};
}

# force skipped DNS resolution, if unset
setting('dns')->{hosts_file} ||= '/etc/hosts';
setting('dns')->{no} ||= ['fe80::/64','169.254.0.0/16'];

# legacy config item names

config->{'devport_vlan_limit'} =
  config->{'deviceport_vlan_membership_threshold'}
  if setting('deviceport_vlan_membership_threshold')
     and not setting('devport_vlan_limit');
delete config->{'deviceport_vlan_membership_threshold'};

config->{'schedule'} = config->{'housekeeping'}
  if setting('housekeeping') and not setting('schedule');
delete config->{'housekeeping'};

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

# set max outstanding requests for AnyEvent::DNS
$ENV{'PERL_ANYEVENT_MAX_OUTSTANDING_DNS'}
  = setting('dns')->{max_outstanding} || 50;
$ENV{'PERL_ANYEVENT_HOSTS'}
  = setting('dns')->{hosts_file} || '/etc/hosts';

# always set this
$ENV{DBIC_TRACE_PROFILE} = 'console';

true;
