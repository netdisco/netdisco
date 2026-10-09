package App::Netdisco::Web::Plugin::Report::IpInventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use NetAddr::IP::Lite ':lower';
use POSIX qw/strftime/;

register_report(
    {   category     => 'IP',
        tag          => 'ipinventory',
        label        => 'IP Inventory',
        provides_csv => 1,
        api_endpoint => 1,
        api_parameters => [
          subnet => {
            description => 'IP Prefix to search',
            required => 1,
          },
          daterange => {
            description => 'Date range to search',
            default => ('1970-01-01 to '. strftime('%Y-%m-%d', gmtime)),
          },
          age_invert => {
            description => 'Results should NOT be within daterange',
            type => 'boolean',
            default => 'false',
          },
          limit => {
            description => 'Maximum number of historical records',
            enum => [qw/32 64 128 256 512 1024 2048 4096 8192/],
            default => '2048',
          },
          never => {
            description => 'Include in the report IPs never seen',
            type => 'boolean',
            default => 'false',
          },
        ],
    }
);

get '/ajax/content/report/ipinventory' => require_login sub {

    # Default to something simple with no results to prevent
    # "Search failed!" error
    (my $subnet = (param('subnet') || '0.0.0.0/32')) =~ s/\s//g;
    $subnet = NetAddr::IP::Lite->new($subnet);
    $subnet = NetAddr::IP::Lite->new('0.0.0.0/32')
      if (! $subnet) or ($subnet->addr eq '0.0.0.0');

    my $agenot = param('age_invert') || '0';

    my $daterange = param('daterange')
      || ('1970-01-01 to '. strftime('%Y-%m-%d', gmtime));
    my ( $start, $end ) = $daterange =~ /(\d+-\d+-\d+)/gmx;

    my $limit = param('limit') || 256;
    my $never = param('never') || '0';

    # We need a reasonable limit to prevent a potential DoS, especially if
    # 'never' is true.  TODO: Need better input validation, both JS and
    # server-side to provide user feedback
    $limit = 8192 if $limit > 8192;

    my @results = schema(vars->{'tenant'})->resultset('DeviceIp')->ip_inventory($subnet, {
        never  => $never,
        age_invert => $agenot,
        limit  => $limit,
        (($start and $end) ? (start => "$start 00:00:00", end => "$end 23:59:59") : ()),
    })->all;
    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/report/ipinventory.tt', { results => $json }, { layout => 'noop' };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/ipinventory_csv.tt', { results => \@results, }, { layout => 'noop' };
    }
};

1;
