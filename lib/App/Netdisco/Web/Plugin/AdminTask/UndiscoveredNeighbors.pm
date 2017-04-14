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
        = schema('netdisco')->resultset('Virtual::UndiscoveredNeighbors')
        ->order_by('ip')->hri->all;
    return unless scalar @results;

    # Don't include devices excluded from discovery by config
    # but only if the number of devices is small, as it triggers a
    # SELECT per device to check.
    if (scalar @results < 50) {
        @results
            = grep { is_discoverable( $_->{'remote_ip'}, $_->{'remote_type'} ) }
            @results;
    }
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
