package App::Netdisco::Web::Plugin::Search::Device;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use List::MoreUtils ();

use App::Netdisco::Web::Plugin;

my @DEFAULT_FIELDS = qw/ip dns name location model os_ver serial chassis_id/;

register_search_tab({
    tag => 'device',
    label => 'Device',
    provides_csv => 1,
    api_endpoint => 1,
    api_parameters => [
      q => {
        description => 'Partial match of Device contact, serial, chassis ID, module serials, location, name, description, dns, or any IP alias. Optional if "limit" and "offset" are both given, to return all devices.',
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
      fields => {
        description => 'Comma-separated list of fields to return. Default: ip,dns,name,location,model,os_ver,serial,chassis_id. Any Device table column is valid (e.g. vendor,os,layers,last_discover,last_macsuck,last_arpnip). Use "all" for every column. Extra join: device_auth_tag.',
      },
      seeallcolumns => {
        description => 'Deprecated, use fields=all instead. If true and "fields" is not given, all columns of the Device will be shown.',
        type => 'boolean',
        default => 'false',
      },
      limit => {
        description => 'Maximum number of devices to return. Required, along with "offset", if neither "q" nor any filter parameter is given.',
      },
      offset => {
        description => 'Number of devices to skip (for paging). Default: 0.',
      },
    ],
});

# device with various properties or a default match-all
get '/ajax/content/search/device' => require_login sub {
    my $has_opt = List::MoreUtils::any { param($_) }
      qw/name location dns ip description model os os_ver vendor layers mac/;

    my $fields = param('fields') || (param('seeallcolumns') ? 'all' : '');
    my @cols = $fields eq 'all' ? ()
             : $fields          ? split(/\s*,\s*/, $fields)
             :                    @DEFAULT_FIELDS;

    my $want_tag = List::MoreUtils::any { $_ eq 'device_auth_tag' } @cols;
    @cols = grep { $_ ne 'device_auth_tag' } @cols;

    my $rs_columns = schema(vars->{'tenant'})->resultset('Device');
    $rs_columns = $rs_columns->columns(\@cols) if @cols;
    $rs_columns = $rs_columns->search(undef, {
      join => 'community',
      '+columns' => [{ device_auth_tag => 'community.snmp_auth_tag_read' }],
    }) if $want_tag;

    my $rs;
    if ($has_opt) {
        $rs = $rs_columns->search_by_field( scalar params );
    }
    elsif (param('q')) {
        $rs = $rs_columns->search_fuzzy( param('q') );
    }
    elsif (defined param('limit') and defined param('offset')) {
        $rs = $rs_columns->search(undef, { order_by => [qw/me.dns me.ip/] });
    }
    else {
        send_error( 'Missing query - provide "q", a filter parameter,'
          .' or both "limit" and "offset"', 400 );
    }

    my $limit  = param('limit');
    my $offset = param('offset');

    if ($limit or $offset) {
        # paginate on device ip before with_times/with_module_serials: combining
        # LIMIT with the module_serials has_many join forces DBIC to wrap the
        # query in a subquery, which cannot re-express with_times' raw-SQL
        # computed columns (eg. me.creation) in the outer SELECT, and crashes
        my @page_ips = $rs->search(undef, {
          columns => ['ip'],
          ($limit  ? (rows   => int($limit))  : ()),
          ($offset ? (offset => int($offset)) : ()),
        })->get_column('ip')->all;
        return unless @page_ips;

        $rs = $rs_columns->search({ 'me.ip' => { -in => \@page_ips } },
                                   { order_by => [qw/me.dns me.ip/] });
    }

    my @results = $rs->with_times->with_module_serials # must come after search_fuzzy
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
