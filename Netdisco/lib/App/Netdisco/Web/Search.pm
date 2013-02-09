package App::Netdisco::Web::Search;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use NetAddr::IP::Lite ':lower';

hook 'before' => sub {
  # view settings for node options
  var('node_options' => [
    { name => 'stamps', label => 'Time Stamps', default => 'on' },
  ]);

  # view settings for device options
  var('device_options' => [
    { name => 'matchall', label => 'Match All Options', default => 'on' },
  ]);

  return unless (request->path eq uri_for('/search')->path
      or index(request->path, uri_for('/ajax/content/search')->path) == 0);

  foreach my $col (@{ var('node_options') }) {
      next unless $col->{default} eq 'on';
      params->{$col->{name}} = 'checked'
        if not param('tab') or param('tab') ne 'node';
  }

  foreach my $col (@{ var('device_options') }) {
      next unless $col->{default} eq 'on';
      params->{$col->{name}} = 'checked'
        if not param('tab') or param('tab') ne 'device';
  }
};

hook 'before_template' => sub {
  my $tokens = shift;

  # new searches will use these defaults in their sidebars
  $tokens->{search_node}   = uri_for('/search', {tab => 'node'});
  $tokens->{search_device} = uri_for('/search', {tab => 'device'});

  foreach my $col (@{ var('node_options') }) {
      next unless $col->{default} eq 'on';
      $tokens->{search_node}->query_param($col->{name}, 'checked');
  }

  foreach my $col (@{ var('device_options') }) {
      next unless $col->{default} eq 'on';
      $tokens->{search_device}->query_param($col->{name}, 'checked');
  }

  return unless (request->path eq uri_for('/search')->path
      or index(request->path, uri_for('/ajax/content/search')->path) == 0);

  # used in the device search sidebar template to set selected items
  foreach my $opt (qw/model vendor os_ver/) {
      my $p = (ref [] eq ref param($opt) ? param($opt)
                                          : (param($opt) ? [param($opt)] : []));
      $tokens->{"${opt}_lkp"} = { map { $_ => 1 } @$p };
  }
};

get '/search' => sub {
    my $q = param('q');
    if (not param('tab')) {
        if (not $q) {
            redirect uri_for('/');
        }

        # pick most likely tab for initial results
        if ($q =~ m/^\d+$/) {
            params->{'tab'} = 'vlan';
        }
        else {
            my $s = schema('netdisco');
            if ($q =~ m{^[a-f0-9.:/]+$}i) {
                my $ip = NetAddr::IP::Lite->new($q);
                my $nd = $s->resultset('Device')->search_by_field({ip => $q});
                if ($ip and $nd->count) {
                    if ($nd->count == 1) {
                        # redirect to device details for the one device
                        redirect uri_for('/device',
                          {tab => 'details', q => $q, f => ''});
                    }
                    params->{'tab'} = 'device';
                }
                else {
                    # this will match for MAC addresses
                    # and partial IPs (subnets?)
                    params->{'tab'} = 'node';
                }
            }
            else {
                my $nd = $s->resultset('Device')->search({dns => { '-ilike' => "\%$q\%" }});
                if ($nd->count) {
                    if ($nd->count == 1) {
                        # redirect to device details for the one device
                        redirect uri_for('/device',
                          {tab => 'details', q => $nd->first->ip, f => ''});
                    }
                    params->{'tab'} = 'device';
                }
                elsif ($s->resultset('DevicePort')
                         ->search({name => "\%$q\%"})->count) {
                    params->{'tab'} = 'port';
                }
            }
            params->{'tab'} ||= 'node';
        }
    }

    # used in the device search sidebar to populate select inputs
    my $model_list  = [ schema('netdisco')->resultset('Device')->get_distinct_col('model')  ];
    my $os_ver_list = [ schema('netdisco')->resultset('Device')->get_distinct_col('os_ver') ];
    my $vendor_list = [ schema('netdisco')->resultset('Device')->get_distinct_col('vendor') ];

    template 'search', {
      model_list  => $model_list,
      os_ver_list => $os_ver_list,
      vendor_list => $vendor_list,
    };
};

true;
