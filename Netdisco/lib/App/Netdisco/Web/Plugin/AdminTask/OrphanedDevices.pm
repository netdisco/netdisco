package App::Netdisco::Web::Plugin::AdminTask::OrphanedDevices;

use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_admin_task(
    {   tag          => 'orphaned',
        label        => 'Orphaned Devices / Networks',
        provides_csv => 1,
    }
);

get '/ajax/content/admin/orphaned' => require_role admin => sub {

    my @tree = schema('netdisco')->resultset('Virtual::UnDirEdgesAgg')
        ->search( undef, { prefetch => 'device' } )->hri->all;

    my @orphans
        = schema('netdisco')->resultset('Virtual::OrphanedDevices')->search()
        ->order_by('ip')->hri->all;

    return unless ( scalar @tree || scalar @orphans );

    my @ordered;

    if ( scalar @tree ) {
        my %tree = map { $_->{'left_ip'} => $_ } @tree;

        my $current_graph = 0;
        my %visited       = ();
        my @to_visit      = ();
        foreach my $node ( keys %tree ) {
            next if exists $visited{$node};

            $current_graph++;
            @to_visit = ($node);
            while (@to_visit) {
                my $node_to_visit = shift @to_visit;

                $visited{$node_to_visit} = $current_graph;

                push @to_visit,
                    grep { !exists $visited{$_} }
                    @{ $tree{$node_to_visit}->{'links'} };
            }
        }

        my @graphs = ();
        foreach my $key ( keys %visited ) {
            push @{ $graphs[ $visited{$key} - 1 ] }, $tree{$key}->{'device'};
        }

        @ordered = sort { scalar @{$b} <=> scalar @{$a} } @graphs;
    }

    return if ( scalar @ordered < 2 && !scalar @tree );

    if ( request->is_ajax ) {
        template 'ajax/admintask/orphaned.tt',
            {
            orphans => \@orphans,
            graphs  => \@ordered,
            },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/admintask/orphaned_csv.tt',
            {
            orphans => \@orphans,
            graphs  => \@ordered,
            },
            { layout => undef };
    }
};

1;
