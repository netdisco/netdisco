package App::Netdisco::Web::TypeAhead;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Util::Web (); # for sort_port
use HTML::Entities 'encode_entities';
use List::MoreUtils ();

ajax '/ajax/data/queue/typeahead/backend' => require_role admin => sub {
    return '[]' unless setting('navbar_autocomplete');

    my $q = quotemeta( param('query') || param('term') || param('backend') );
    my @backends =
     grep { $q ? m/$q/ : true }
     List::MoreUtils::uniq
     sort
     grep { defined }
     schema(vars->{'tenant'})->resultset('DeviceSkip')->get_distinct_col('backend');

    content_type 'application/json';
    to_json \@backends;
};

ajax '/ajax/data/queue/typeahead/username' => require_role admin => sub {
    return '[]' unless setting('navbar_autocomplete');

    my $q = quotemeta( param('query') || param('term') || param('username') );
    my @users =
     grep { $q ? m/$q/ : true }
     List::MoreUtils::uniq
     sort
     grep { defined }
     schema(vars->{'tenant'})->resultset('Admin')->get_distinct_col('username');

    content_type 'application/json';
    to_json \@users;
};

ajax '/ajax/data/queue/typeahead/action' => require_role admin => sub {
    return '[]' unless setting('navbar_autocomplete');

    my @actions = ();
    my @core_plugins = @{ setting('worker_plugins') || [] };
    my @user_plugins = @{ setting('extra_worker_plugins') || [] };

    # load worker plugins for our action
    foreach my $plugin (@user_plugins, @core_plugins) {
      $plugin =~ s/^X::/+App::NetdiscoX::Worker::Plugin::/;
      $plugin = 'App::Netdisco::Worker::Plugin::'. $plugin
        if $plugin !~ m/^\+/;
      $plugin =~ s/^\+//;

      next if $plugin =~ m/::Plugin::Internal::/;

      if ($plugin =~ m/::Plugin::(Hook::[^:]+)/) {
          push @actions, lc $1;
          next;
      }

      next if $plugin =~ m/::Plugin::Hook$/;
      next unless $plugin =~ m/::Plugin::([^:]+)(?:::|$)/;

      push @actions, lc $1;
    }

    push @actions,
     schema(vars->{'tenant'})->resultset('Admin')->get_distinct_col('action');

    my $q = quotemeta( param('query') || param('term') || param('action') );

    content_type 'application/json';
    to_json [
      grep { $q ? m/^$q/ : true }
      grep { defined }
      List::MoreUtils::uniq
      sort
      @actions
    ];
};

ajax '/ajax/data/queue/typeahead/status' => require_role admin => sub {
    return '[]' unless setting('navbar_autocomplete');

    my $q = quotemeta( param('query') || param('term') || param('status') );
    my @actions =
     grep { $q ? m/^$q/ : true }
     qw(Queued Running Done Info Deferred Error);

    content_type 'application/json';
    to_json \@actions;
};

ajax '/ajax/data/devicename/typeahead' => require_login sub {
    return '[]' unless setting('navbar_autocomplete');

    my $q = param('query') || param('term');
    my $set = schema(vars->{'tenant'})->resultset('Device')->search_fuzzy($q);

    content_type 'application/json';
    to_json [map {encode_entities($_->dns || $_->name || $_->ip)} $set->all];
};

ajax '/ajax/data/deviceip/typeahead' => require_login sub {
    my $q = param('query') || param('term');
    my $set = schema(vars->{'tenant'})->resultset('Device')->search_fuzzy($q);

    my @data = ();
    while (my $d = $set->next) {
        my $label = $d->ip;
        if ($d->dns or $d->name) {
            $label = sprintf '%s (%s)',
              ($d->dns || $d->name), $d->ip;
        }
        push @data, { label => $label, value => $d->ip };
    }

    content_type 'application/json';
    to_json \@data;
};

ajax '/ajax/data/port/typeahead' => require_login sub {
    my $dev  = param('dev1')  || param('dev2');
    my $port = param('port1') || param('port2');
    send_error('Missing device', 400) unless $dev;

    my $device = schema(vars->{'tenant'})->resultset('Device')
      ->find({ip => $dev});
    send_error('Bad device', 400) unless $device;

    my $set = $device->ports({},{order_by => 'port'});
    $set = $set->search({port => { -ilike => "\%$port\%" }})
      if $port;

    my $results = [
      map  {{ label => (sprintf "%s (%s)", $_->port, ($_->name || '')), value => $_->port }}
      sort { &App::Netdisco::Util::Web::sort_port($a->port, $b->port) } $set->all
    ];

    content_type 'application/json';
    to_json \@$results;
};

ajax '/ajax/data/subnet/typeahead' => require_login sub {
    my $q = param('query') || param('term');
    $q = "$q\%" if $q !~ m/\%/;
    my $nets = schema(vars->{'tenant'})->resultset('Subnet')->search(
           { 'me.net::text'  => { '-ilike' => $q }},
           { columns => ['net'], order_by => 'net' } );

    content_type 'application/json';
    to_json [map {$_->net} $nets->all];
};

true;
