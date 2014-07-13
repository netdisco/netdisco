package App::Netdisco::Util::Graph;

use App::Netdisco;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::DNS qw/hostname_from_ip ipv4_from_hostname/;
use Graph::Undirected ();
use GraphViz ();

use base 'Exporter';
our @EXPORT = ('graph');
our @EXPORT_OK = qw/
  graph_each
  graph_addnode
  make_graph
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

# nothing to see here, please move along...
our ($ip, $label, $isdev, $devloc, %GRAPH, %GRAPH_SPEED);

=head1 NAME

App::Netdisco::Util::Graph

=head1 SYNOPSIS

 $ brew install graphviz   <-- install graphviz on your system
 
 $ ~/bin/localenv bash
 $ cpanm --notest Graph GraphViz
 $ mkdir ~/graph
 
 use App::Netdisco::Util::Graph 'graph';
 graph;

=head1 DESCRIPTION

Generate GraphViz output from Netdisco data. Requires that the L<Graph> and
L<GraphViz> distributions be installed.

Requires the same config as for Netdisco 1, but within a C<graphviz> key.  See
C<share/config.yml> in the source distribution for an example.

The C<graph> subroutine is exported by default. The C<:all> tag will export
all subroutines.

=head1 EXPORT

=item graph()

Creates netmap of network.

=cut

sub graph {
    my %CONFIG = %{ setting('graph') };

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
    my $month = sprintf("%d%02d",$year+1900,$mon+1);

    info "graph() - Creating Graphs";
    my $G = make_graph();

    unless (defined $G){
        print "graph() - make_graph() failed.  Try running with debug (-D).";
        return;
    }

    my @S = $G->connected_components;

    # Count number of nodes in each subgraph
    my %S_count;
    for (my $i=0;$i< scalar @S;$i++){
        $S_count{$i} = scalar @{$S[$i]};
    }

    foreach my $subgraph (sort { $S_count{$b} <=> $S_count{$a} } keys %S_count){
        my $SUBG = $G->copy;
        print "\$S[$subgraph] has $S_count{$subgraph} nodes.\n";

        # Remove other subgraphs from this one
        my %S_notme = %S_count;
        delete $S_notme{$subgraph};
        foreach my $other (keys %S_notme){
            print "Removing Non-connected nodes: ",join(',',@{$S[$other]}),"\n";
            $SUBG->delete_vertices(@{$S[$other]})
        }

        # Create the subgraph
        my $timeout = defined $CONFIG{graph_timeout} ? $CONFIG{graph_timeout} : 60;

        eval {
            alarm($timeout*60);
            graph_each($SUBG,'');
            alarm(0);
        };
        if ($@) {
            if ($@ =~ /timeout/){
                print "! Creating Graph timed out!\n";
            } else {
                print "\n$@\n";
            }
        }

        # Facility to create subgraph for each non-connected network segment.
        # Right now, let's just make the biggest one only.
        last;
    }
}

=head1 EXPORT_OK

=item graph_each($graph_obj, $name)

Generates subgraph. Does actual GraphViz calls.

=cut

sub graph_each  {
    my ($G, $name) = @_;
    my %CONFIG = %{ setting('graph') };
    info "Creating new Graph";

    my $graph_defs = {
                     'bgcolor' => $CONFIG{graph_bg}         || 'black',
                     'color'   => $CONFIG{graph_color}      || 'white',
                     'overlap' => $CONFIG{graph_overlap}    || 'scale',
                     'fontpath'=> _homepath('graph_fontpath',''),
                     'ranksep' => $CONFIG{graph_ranksep}    || 0.3,
                     'nodesep' => $CONFIG{graph_nodesep}    || 2,
                     'ratio'   => $CONFIG{graph_ratio}      || 'compress',
                     'splines' => ($CONFIG{graph_splines} ? 'true' : 'false'),
                     'fontcolor' => $CONFIG{node_fontcolor} || 'white',
                     'fontname'  => $CONFIG{node_font}      || 'lucon',
                     'fontsize'  => $CONFIG{node_fontsize}  || 12,
                     };
    my $edge_defs  = {
                     'color' => $CONFIG{edge_color}         || 'wheat',
                     };
    my $node_defs  = {
                     'shape'     => $CONFIG{node_shape}     || 'box',
                     'fillcolor' => $CONFIG{node_fillcolor} || 'dimgrey',
                     'fontcolor' => $CONFIG{node_fontcolor} || 'white',
                     'style'     => $CONFIG{node_style}     || 'filled',
                     'fontname'  => $CONFIG{node_font}      || 'lucon',
                     'fontsize'  => $CONFIG{node_fontsize}  || 12,
                     'fixedsize' => ($CONFIG{node_fixedsize} ? 'true' : 'false'),
                     };
    $node_defs->{height} = $CONFIG{node_height} if defined $CONFIG{node_height};
    $node_defs->{width}  = $CONFIG{node_width}  if defined $CONFIG{node_width};

    my $epsilon = undef;
    if (defined $CONFIG{graph_epsilon}){
        $epsilon = "0." . '0' x $CONFIG{graph_epsilon} . '1';
    }

    my %gv = (
               directed => 0,
               layout   => $CONFIG{graph_layout} || 'twopi',
               graph    => $graph_defs,
               node     => $node_defs,
               edge     => $edge_defs,
               width    => $CONFIG{graph_x}      || 30,
               height   => $CONFIG{graph_y}      || 30,
               epsilon  => $epsilon,
              );

    my $gv = GraphViz->new(%gv);

    my %node_map = ();
    my @nodes = $G->vertices;

    foreach my $dev (@nodes){
        my $node_name = graph_addnode($gv,$dev);
        $node_map{$dev} = $node_name;
    }

    my $root_ip = defined $CONFIG{root_device}
      ? (ipv4_from_hostname($CONFIG{root_device}) || $CONFIG{root_device})
      : undef;

    if (defined $root_ip and defined $node_map{$root_ip}){
        my $gv_root_name = $gv->_quote_name($root_ip);
        if (defined $gv_root_name){
            $gv->{GRAPH_ATTRS}->{root}=$gv_root_name;
        }
    }

    my @edges = $G->edges;

    while (my $e = shift @edges){
        my $link = $e->[0];
        my $dest = $e->[1];
        my $speed = $GRAPH_SPEED{$link}->{$dest}->{speed};

        if (!defined($speed)) {
            info "  ! No link speed for $link -> $dest";
            $speed = 0;
        }

        my %edge = ();
        my $val = ''; my $suffix = '';

        if ($speed =~ /^([\d.]+)\s+([a-z])bps$/i) {
            $val = $1; $suffix = $2;
        }

        if ( ($suffix eq 'k') or ($speed =~ m/(t1|ds3)/i) ){
            $edge{color} = 'green';
            $edge{style} = 'dotted';
        }

        if ($suffix eq 'M'){
            if ($val < 10.0){
                $edge{color} = 'green';
                #$edge{style} = 'dotted';
                $edge{style} = 'dashed';
            } elsif ($val < 100.0){
                $edge{color} = '#8b7e66';
                #$edge{style} = 'normal';
                $edge{style} = 'solid';
            } else {
                $edge{color} = '#ffe7ba';
                $edge{style} = 'solid';
            }
        }

        if ($suffix eq 'G'){
            #$edge{style} = 'bold';
            $edge{color} = 'cyan1';
        }

        # Add extra styles to edges (mainly for modifying width)
        if(defined $CONFIG{edge_style}) {
            $edge{style} .= "," . $CONFIG{edge_style};
        }

        $gv->add_edge($link => $dest, %edge );
    }

    info "Ignore all warnings about node size";

    if (defined $CONFIG{graph_raw} and $CONFIG{graph_raw}){
        my $graph_raw = _homepath('graph_raw');
        info "  Creating raw graph: $graph_raw";
        $gv->as_canon($graph_raw);
    }

    if (defined $CONFIG{graph} and $CONFIG{graph}){
        my $graph_gif = _homepath('graph');
        info "  Creating graph: $graph_gif";
        $gv->as_gif($graph_gif);
    }

    if (defined $CONFIG{graph_png} and $CONFIG{graph_png}){
        my $graph_png = _homepath('graph_png');
        info "  Creating png graph: $graph_png";
        $gv->as_png($graph_png);
    }

    if (defined $CONFIG{graph_map} and $CONFIG{graph_map}){
        my $graph_map = _homepath('graph_map');
        info "  Creating CMAP : $graph_map";
        $gv->as_cmap($graph_map);
    }

    if (defined $CONFIG{graph_svg} and $CONFIG{graph_svg}){
        my $graph_svg = _homepath('graph_svg');
        info "  Creating SVG : $graph_svg";
        $gv->as_svg($graph_svg);
    }
}

=item graph_addnode($graphviz_obj, $node_ip)

Checks for mapping settings in config file and adds node to the GraphViz
object.

=cut

sub graph_addnode {
    my $gv = shift;
    my %CONFIG = %{ setting('graph') };
    my %node = ();

    $ip     = shift;
    $label  = $GRAPH{$ip}->{dns};
    $isdev  = $GRAPH{$ip}->{isdev};
    $devloc = $GRAPH{$ip}->{location};

    $label = "($ip)" unless defined $label;
    my $domain_suffix = setting('domain_suffix') || '';
    $label =~ s/$domain_suffix$//;
    $node{label} = $label;

    # Dereferencing the scalar by name below
    #   requires that the variable be non-lexical (not my)
    #   we'll create some local non-lexical versions
    #   that will expire at the end of this block
    # Node Mappings
    foreach my $map (@{ $CONFIG{'node_map'} || [] }){
        my ($var, $regex, $attr, $val) = split(':', $map);

        { no strict 'refs';
           $var = ${"$var"};
        }
        next unless defined $var;

        if ($var =~ /$regex/) {
            debug "  graph_addnode - Giving node $ip $attr = $val";
            $node{$attr} = $val;
        }
    }

    # URL for image maps FIXME for non-root hosting
    if ($isdev) {
        $node{URL} = "/device?&q=$ip";
    }
    else {
        $node{URL} = "/search?tab=node&q=$ip";
        # Overrides any colors given to nodes above. Bug 1094208
        $node{fillcolor} = $CONFIG{'node_problem'} || 'red';
    }

    if ($CONFIG{'graph_clusters'} && $devloc) {
        # This odd construct works around a bug in GraphViz.pm's
        # quoting of cluster names.  If it has a name with spaces,
        # it'll just quote it, resulting in creating a subgraph name
        # of cluster_"location with spaces".  This is an illegal name
        # according to the dot grammar, so if the name matches the
        # problematic regexp we make GraphViz.pm generate an internal
        # name by using a leading space in the name.
        #
        # This is bug ID 16912 at rt.cpan.org -
        # http://rt.cpan.org/NoAuth/Bug.html?id=16912
        #
        # Another bug, ID 11514, prevents us from using a combination
        # of name and label attributes to hide the extra space from
        # the user.  However, since it's just a space, hopefully it
        # won't be too noticable.
        my($loc) = $devloc;
        $loc = " " . $loc if ($loc =~ /^[a-zA-Z](\w| )*$/);
        $node{cluster} = { name => $loc };
    }

    my $rv = $gv->add_node($ip, %node);
    return $rv;
}

=head2 make_graph()

Returns C<Graph::Undirected> object that represents the discovered network.

Graph is made by loading all the C<device_port> entries that have a neighbor,
using them as edges. Then each device seen in those entries is added as a
vertex.

Nodes without topology information are not included.

=cut

sub make_graph {
    my $G = Graph::Undirected->new();

    my $devices = schema('netdisco')->resultset('Device')
        ->search({}, { columns => [qw/ip dns location /] });
    my $links = schema('netdisco')->resultset('DevicePort')
        ->search({remote_ip => { -not => undef }},
                 { columns => [qw/ip remote_ip speed remote_type/]});
    my %aliases = map {$_->alias => $_->ip}
        schema('netdisco')->resultset('DeviceIp')
          ->search({}, { columns => [qw/ip alias/] })->all;

    my %devs = ( map {($_->ip => $_->dns)}      $devices->all );
    my %locs = ( map {($_->ip => $_->location)} $devices->all );

    # Check for no topology info
    unless ($links->count > 0) {
        debug "make_graph() - No topology information. skipping.";
        return undef;
    }

    my %link_seen = ();
    my %linkmap   = ();

    while (my $link = $links->next) {
        my $source = $link->ip;
        my $dest   = $link->remote_ip;
        my $speed  = $link->speed;
        my $type   = $link->remote_type;

        # Check for Aliases
        if (defined $aliases{$dest}) {
            # Set to root device
            $dest = $aliases{$dest};
        }

        # Remove loopback - After alias check (bbaetz)
        if ($source eq $dest) {
            debug "  make_graph() - Loopback on $source";
            next;
        }

        # Skip IP Phones
        if (defined $type and $type =~ /ip.phone/i) {
            debug "  make_graph() - Skipping IP Phone. $source -> $dest ($type)";
            next;
        }
        next if exists $link_seen{$source}->{$dest};

        push(@{ $linkmap{$source} }, $dest);

        # take care of reverse too
        $link_seen{$source}->{$dest}++;
        $link_seen{$dest}->{$source}++;

        $GRAPH_SPEED{$source}->{$dest}->{speed}=$speed;
        $GRAPH_SPEED{$dest}->{$source}->{speed}=$speed;
    }

    foreach my $link (keys %linkmap) {
        foreach my $dest (@{ $linkmap{$link} }) {

            foreach my $side ($link, $dest) {
                unless (defined $GRAPH{$side}) {
                    my $is_dev = exists $devs{$side};
                    my $dns = $is_dev ?
                              $devs{$side} :
                              hostname_from_ip($side);

                    # Default to IP if no dns
                    $dns = defined $dns ? $dns : "($side)";

                    $G->add_vertex($side);
                    debug "  make_graph() - add_vertex('$side')";

                    $GRAPH{$side}->{dns} = $dns;
                    $GRAPH{$side}->{isdev} = $is_dev;
                    $GRAPH{$side}->{seen}++;
                    $GRAPH{$side}->{location} = $locs{$side};
                }
            }

            $G->add_edge($link,$dest);
            debug "  make_graph - add_edge('$link','$dest')";
        }
    }

    return $G;
}

sub _homepath {
    my ($path, $default) = @_;

    my $home = $ENV{NETDISCO_HOME};
    my $item = setting('graph')->{$path} || $default;
    return undef unless defined($item);

    if ($item =~ m,^/,) {
        return $item;
    }
    else {
        $home =~ s,/*$,,;
        return $home . "/" . $item;
    }
}

1;
