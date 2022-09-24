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

# just to note a problem with this query:
# using DeviceSkip to see if discover is blocked, but that table only shows
# blocked actions on backends not permitted, so there may be a backend running
# that permits the action, we would not know.

get '/ajax/content/admin/undiscoveredneighbors' => require_role admin => sub {
    my @results
        = schema(vars->{'tenant'})->resultset('Virtual::UndiscoveredNeighbors')->hri->all;
    return unless scalar @results;

    if ( request->is_ajax ) {
        template 'ajax/admintask/undiscoveredneighbors.tt',
            { results => \@results, },
            { layout  => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/admintask/undiscoveredneighbors_csv.tt',
            { results => \@results, },
            { layout  => undef };
    }
};

1;
