package App::Netdisco::Web::Plugin::AdminTask::UndiscoveredNeighbors;

use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use App::Netdisco::Util::Device qw/is_discoverable/;

use App::Netdisco::Web::Plugin;

register_admin_task(
    {   tag          => 'undiscoveredneighbors',
        label        => 'Undiscovered Neighbors',
        provides_csv => 1,
    }
);

get '/ajax/content/admin/undiscoveredneighbors' => require_role admin => sub {
    my @results
        = schema('netdisco')->resultset('Virtual::UndiscoveredNeighbors')->hri->all;
    return unless scalar @results;

    # Don't include devices excluded from discovery by config
    my @discoverable_results = ();
    foreach my $r (@results) {
      # create a new row object to avoid hitting the DB in get_device()
      my $dev = schema('netdisco')->resultset('Device')->new({ip => $r->{remote_ip}});
      next unless is_discoverable( $dev, $r->{remote_type} );
      next if (not setting('discover_waps')) and $r->{remote_is_wap};
      next if (not setting('discover_phones')) and $r->{remote_is_phone};
      push @discoverable_results, $r;
    }
    return unless scalar @discoverable_results;

    if ( request->is_ajax ) {
        template 'ajax/admintask/undiscoveredneighbors.tt',
            { results => \@discoverable_results, },
            { layout  => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/admintask/undiscoveredneighbors_csv.tt',
            { results => \@discoverable_results, },
            { layout  => undef };
    }
};

1;
