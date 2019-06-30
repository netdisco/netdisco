package App::Netdisco::Web::Search;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
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
    my $s = schema('netdisco');

    if (not param('tab')) {
        if (not $q) {
            return redirect uri_for('/')->path;
        }

        # pick most likely tab for initial results
        if ($q =~ m/^\d+$/) {
            params->{'tab'} = 'vlan';
        }
        else {
            my $nd = $s->resultset('Device')->search_fuzzy($q);
            my ($likeval, $likeclause) = sql_match($q);
            my $mac = NetAddr::MAC->new($q);

            undef $mac if
              ($mac and $mac->as_ieee
              and (($mac->as_ieee eq '00:00:00:00')
                or ($mac->as_ieee !~ m/$RE{net}{MAC}/)));

            if ($nd and $nd->count) {
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
                     ->search({
                       -or => [
                         {name => $likeclause},
                         ((!defined $mac or $mac->errstr)
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
    my $model_list  = [ $s->resultset('Device')->get_distinct_col('model')  ];
    my $os_list     = [ $s->resultset('Device')->get_distinct_col('os') ];
    my $os_ver_list = [ $s->resultset('Device')->get_distinct_col('os_ver') ];
    my $vendor_list = [ $s->resultset('Device')->get_distinct_col('vendor') ];

    template 'search', {
      search => params->{'tab'},
      model_list  => $model_list,
      os_list     => $os_list,
      os_ver_list => $os_ver_list,
      vendor_list => $vendor_list,
    };
};

true;
