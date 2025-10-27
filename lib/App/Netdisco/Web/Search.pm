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

            if ($s->resultset('DevicePort')
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
