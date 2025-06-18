package App::Netdisco::Web::Plugin::Search::Device;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use List::MoreUtils ();

use App::Netdisco::Web::Plugin;

register_search_tab({
    tag => 'device',
    label => 'Device',
    provides_csv => 1,
    api_endpoint => 1,
    api_parameters => [
      q => {
        description => 'Partial match of Device contact, serial, chassis ID, module serials, location, name, description, dns, or any IP alias',
      },
      name => {
        description => 'Partial match of the Device name',
      },
      location => {
        description => 'Partial match of the Device location',
      },
      dns => {
        description => 'Partial match of any of the Device IP aliases',
      },
      ip => {
        description => 'IP or IP Prefix within which the Device must have an interface address',
      },
      description => {
        description => 'Partial match of the Device description',
      },
      mac => {
        description => 'MAC Address of the Device or any of its Interfaces',
      },
      model => {
        description => 'Exact match of the Device model',
      },
      os => {
        description => 'Exact match of the Device operating system',
      },
      os_ver => {
        description => 'Exact match of the Device operating system version',
      },
      vendor => {
        description => 'Exact match of the Device vendor',
      },
      layers => {
        description => 'OSI Layer which the device must support',
      },
      matchall => {
        description => 'If true, all fields (except "q") must match the Device',
        type => 'boolean',
        default => 'false',
      },
      seeallcolumns => {
        description => 'If true, all columns of the Device will be shown',
        type => 'boolean',
        default => 'false',
      },
    ],
});

# device with various properties or a default match-all
get '/ajax/content/search/device' => require_login sub {
    my $has_opt = List::MoreUtils::any { param($_) }
      qw/name location dns ip description model os os_ver vendor layers mac/;
    my $rs;
    my $rs_columns;
    my $see_all = param('seeallcolumns');

    if ($see_all) {
      $rs_columns = schema(vars->{'tenant'})->resultset('Device');
    }
    else {
      $rs_columns = schema(vars->{'tenant'})->resultset('Device')->columns(
            [   "ip",       "dns",   "name",
                "location", "model", "os_ver", "serial", "chassis_id"
            ]
        );
    }

    if ($has_opt) {
        $rs = $rs_columns->with_times->search_by_field( scalar params );
    }
    else {
        my $q = param('q');
        send_error( 'Missing query', 400 ) unless $q;

        $rs = $rs_columns->with_times->search_fuzzy($q);
    }

    my @results = $rs->with_module_serials # must come after search_fuzzy
                     ->hri->all;
    return unless scalar @results;

    # deduplicate the results as no longer distinct after with_module_serials
    my %seen = ();
    @results = grep { ! $seen{$_->{ip}}++ } @results;

    # flatten device serial, device chassis_id, and module serial(s), and deduplicate
    map {$_->{module_serials} = [ List::MoreUtils::uniq
                                  sort
                                  grep {length}
                                  grep {defined} (
                                    $_->{serial},
                                    $_->{chassis_id},
                                    ( map { $_->{serial} }
                                          @{ $_->{module_serials} } )
                                  )
                                ]} @results;

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/search/device.tt', { results => $json }, { layout => 'noop' };;
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/search/device_csv.tt', { results => \@results, }, { layout => 'noop' };
    }
};

1;
