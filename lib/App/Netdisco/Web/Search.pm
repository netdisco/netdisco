package App::Netdisco::Web::Search;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Util::Web 'sql_match';
use Regexp::Common 'net';
use NetAddr::MAC ();

hook 'before_template' => sub {
  my $tokens = shift;

  return unless (request->path eq uri_for('/search')->path
      or index(request->path, uri_for('/ajax/content/search')->path) == 0);

  # used in the device search sidebar template to set selected items
  foreach my $opt (qw/model vendor os os_ver/) {
      my $p = (ref [] eq ref param($opt) ? param($opt)
                                          : (param($opt) ? [param($opt)] : []));
      $tokens->{"${opt}_lkp"} = { map { $_ => 1 } @$p };
  }
};

# Ports with this MAC. Joined to device, as Port search is, so port rows left
# behind by a deleted device do not count.
sub _mac_port_rs {
    my ($schema, $mac) = @_;
    return $schema->resultset('DevicePort')
      ->search({ 'me.mac' => $mac },
               { join => 'device',
                 columns => [qw/me.ip me.port me.type me.is_uplink/] });
}

# Where a MAC address matching device ports should go. Kept free of param()
# and the schema so xt can pin the decision without a session or a database.
#
# One port goes to the Ports tab filtered to that port. Several ports all on
# one device (a shared base MAC) go to the device details, as the MAC then
# names the device. Ports on several devices fall back to Port search, which
# hides uplinks and non-Ethernet ports unless told otherwise, so those options
# are set from the matched ports or the results could come up empty. A port
# with no type counts as non-Ethernet, as it does in Port search.
#
# Returns undef when no port matched, else { path => ..., query => {...} }.
sub _mac_search_target {
    my ($q, $ports) = @_;
    return undef unless scalar @$ports;

    my %devices = map { $_->ip => 1 } @$ports;

    if (scalar keys %devices == 1) {
        return { path => '/device', query => ((scalar @$ports == 1)
          ? {
            tab => 'ports',
            q => $ports->[0]->ip,
            f => $ports->[0]->port,
            c_mac => 'on',
            c_nodes => 'on',
            c_neighbors => 'on',
          } : {
            tab => 'details',
            q => $ports->[0]->ip,
            f => '',
          }) };
    }

    return { path => '/search', query => {
      tab => 'port',
      q => $q,
      partial => 'on',
      ((grep { $_->is_uplink } @$ports) ? (uplink => 'on') : ()),
      ((grep { ($_->type || '') ne 'ethernetCsmacd' } @$ports)
        ? () : (ethernet => 'on')),
    } };
}

get '/search' => require_login sub {
    my $q = param('q');
    my $s = schema(vars->{'tenant'});

    if (not param('tab')) {
        if (not $q) {
            return redirect uri_for('/')->path;
        }

        # pick most likely tab for initial results
        if ($q =~ m/^[0-9]+$/ and $q < 4096) {
            params->{'tab'} = 'vlan';
        }
        else {
            my $nd = $s->resultset('Device')->search_fuzzy($q);
            my ($likeval, $likeclause) = sql_match($q);
            my $mac = NetAddr::MAC->new(mac => ($q || ''));

            undef $mac if
              ($mac and $mac->as_ieee
              and (($mac->as_ieee eq '00:00:00:00:00:00')
                or ($mac->as_ieee !~ m/^$RE{net}{MAC}$/i)));

            # a port's own MAC is not the device's, so device-first matching
            # lands on the device details page and the MAC is nowhere on it
            # (#1429). Only for a valid MAC, so names and IPs keep matching
            # devices first (#1789).
            my $mac_target = _mac_search_target($q,
              ((defined $mac and not $mac->errstr)
                ? [ _mac_port_rs($s, $mac->as_ieee)->all ] : []));

            if ($mac_target) {
                return redirect uri_for($mac_target->{path},
                  $mac_target->{query})->path_query;
            }
            elsif ($nd and $nd->count) {
                if ($nd->count == 1) {
                    # redirect to device details for the one device
                    return redirect uri_for('/device', {
                      tab => 'details',
                      q => $nd->first->ip,
                      f => '',
                    })->path_query;
                }

                # multiple devices
                params->{'tab'} = 'device';
            }
            elsif ($s->resultset('DevicePort')
                     ->with_properties
                     ->search({
                       -or => [
                         { name => $likeclause },
                         { 'properties.remote_dns' => $likeclause },
                         (((!defined $mac) or $mac->errstr)
                            ? \['mac::text ILIKE ?', $likeval]
                            : {mac => $mac->as_ieee}),
                       ],
                     })->count) {

                params->{'tab'} = 'port';
            }
        }

        # if all else fails
        params->{'tab'} ||= 'node';
    }

    # used in the device search sidebar to populate select inputs
    my $model_list  = [ grep { defined } $s->resultset('Device')->get_distinct_col('model') ];
    my $os_list     = [ grep { defined } $s->resultset('Device')->get_distinct_col('os') ];
    my $vendor_list = [ grep { defined } $s->resultset('Device')->get_distinct_col('vendor') ];

    my %os_vermap = (
      map  { $_ => (join '', map {sprintf '%05s', $_} split m/(\D)/) }
      grep { defined }
      $s->resultset('Device')->get_distinct_col('os_ver')
    );
    my $os_ver_list = [ sort {$os_vermap{$a} cmp $os_vermap{$b}} keys %os_vermap ];

    template 'search', {
      search => params->{'tab'},
      model_list  => $model_list,
      os_list     => $os_list,
      os_ver_list => $os_ver_list,
      vendor_list => $vendor_list,
    }, { layout => 'main' };
};

true;
