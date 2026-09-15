package App::Netdisco::Web::Plugin::Device::SNMP;

use strict;
use warnings;

use Dancer qw(:syntax);
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Swagger;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::SNMP 'decode_and_munge';
use HTML::Entities 'encode_entities';
use Module::Load ();
use Try::Tiny;

register_device_tab({ tag => 'snmp', label => 'SNMP' });

get '/ajax/content/device/snmp' => require_login sub {
    my $device = try { schema(vars->{'tenant'})->resultset('Device')
                                   ->search_for_device( param('q') ) }
       or send_error('Bad Device', 404);

    template 'ajax/device/snmp.tt',
      { device => $device->ip, tree => _get_snmp_data($device->ip, '.1') },
      { layout => 'noop' };
};

# Declared with get rather than the ajax keyword, which matches only a request
# carrying X-Requested-With. htmx sends HX-Request instead, and the tab forms in
# the page shell compensate with an hx-headers attribute; a tree emits one
# fetching element per node, so repeating that string there would be thousands
# of copies of a constant.
get '/ajax/content/device/:ip/snmptree/:base' => require_login sub {
    my $device = try { schema(vars->{'tenant'})->resultset('Device')
                                         ->find( param('ip') ) }
       or send_error('Bad Device', 404);

    my $base = param('base');
    $base =~ m/^\.1(\.\d+)*$/ or send_error('Bad OID Base', 404);

    # Dancer::Plugin::Ajax stamps text/xml on anything declared with its
    # keyword, and htmx will not swap a response typed that way: the request is
    # made, the answer is discarded, and nothing reports it.
    content_type 'text/html';

    return _snmp_placeholder(
      'No data for this device. Admins can request a snapshot in the Details tab.')
      unless $device->oids->count;

    # snapshot should run a loadmibs, but just in case that didn't happen...
    return _snmp_placeholder('No MIB objects. Please run a loadmibs job.')
      unless schema(vars->{'tenant'})->resultset('SNMPObject')->count();

    template 'ajax/device/snmptree.tt',
      { device => $device->ip, nodes => _get_snmp_data($device->ip, $base) },
      { layout => 'noop' };
};

# The two states where there is nothing to browse. One inert row, so the reason
# reaches the reader where the tree would have been.
# The icon beside the search box, swapped out of band so the three states the
# widget this replaced drew in JavaScript survive without any.
sub _snmp_state_icon {
    return sprintf '<i id="nd_snmp_loading_spinner" hx-swap-oob="true" class="%s"></i>',
           encode_entities(shift);
}

sub _snmp_placeholder {
    return sprintf '<li class="nd_snmp-empty">'
                   .'<i class="fas fa-magnifying-glass"></i>%s</li>',
           encode_entities(shift);
}

ajax '/ajax/data/snmp/typeahead' => require_login sub {
    my $term = param('term') or return to_json [];

    my $device = param('ip');
    my $deviceonly = param('deviceonly');
    my ($mib, $leaf) = split m/::/, $term;

    my @found = schema(vars->{'tenant'})->resultset('SNMPObject')
      ->search({ -or => [ 'me.oid'  => $term,
                          'me.oid'  => { -like => ($term .'.%') },
                          -and => [(($mib and $leaf) ? ('me.mib' => $mib, 'me.leaf' => { -ilike => ($leaf .'%') })
                                                     : ('me.leaf' => { -ilike => ('%'. $term .'%') }))] ],
                (($device and $deviceonly) ? ('device_browser.ip' => $device, 'device_browser.value' => { -not => undef }) : ()) },
              { select => [\q{ me.mib || '::' || me.leaf }],
                as => ['qleaf'],
                join => 'device_browser',
                rows => 25, order_by => 'me.oid_parts' })
      ->get_column('qleaf')->all;

    return to_json [] unless scalar @found;

    content_type 'application/json';
    to_json [ sort @found ];
};

get '/ajax/content/device/:ip/snmpsearch' => require_login sub {
    # the search box is named term, which is also what the typeahead beside it
    # sends; str is what the tree widget this replaced used
    my $to_match = (param('term') || param('str')) or return '';
    my $partial = param('partial');
    my $device = param('ip');
    my $deviceonly = param('deviceonly');

    # Dancer::Plugin::Ajax stamps text/xml on anything declared with its
    # keyword, and htmx will not swap a response typed that way: the request is
    # made, the answer is discarded, and nothing reports it.
    content_type 'text/html';

    my ($mib, $leaf) = split m/::/, $to_match;
    my $found = undef;

    if ($partial) {
        $found = schema(vars->{'tenant'})->resultset('SNMPObject')
          ->search({ -or => [ 'me.oid' => $to_match,
                              'me.oid' => { -like => ($to_match .'.%') },
                              -and => [(($mib and $leaf) ? ('me.mib' => $mib, 'me.leaf' => { -ilike => ($leaf .'%') })
                                                         : ('me.leaf' => { -ilike => ($to_match .'%') }))] ],
                     (($device and $deviceonly) ? ('device_browser.ip' => $device, 'device_browser.value' => { -not => undef }) : ()),
                   }, { rows => 1, join => 'device_browser', order_by => 'oid_parts' })->first;
    }
    else {
        $found = schema(vars->{'tenant'})->resultset('SNMPObject')
          ->search({
            (($mib and $leaf) ? (-and => ['me.mib' => $mib, 'me.leaf' => $leaf])
                              : (-or  => ['me.oid' => $to_match, 'me.leaf' => $to_match])),
            (($device and $deviceonly) ? ('device_browser.ip' => $device, 'device_browser.value' => { -not => undef }) : ()),
            },{ rows => 1, join => 'device_browser', order_by => 'oid_parts' })->first;
    }
    # Nothing matched, so the tree the reader is looking at is left exactly as
    # it is and only the state icon changes. htmx swaps nothing when a response
    # holds only out of band content, but the box aims at the tree, so the
    # header says so rather than leaving it to that.
    if (!$found) {
        header 'HX-Reswap' => 'none';
        return _snmp_state_icon('fas fa-circle-exclamation fa-lg');
    }

    $found = $found->oid;
    $found =~ s/^\.1\.?//;
    my @results = ('.1');

    foreach my $part (split m/\./, $found) {
        my $last = $results[-1];
        push @results, "${last}.${part}";
    }

    # The whole path in one response. The widget this replaced took this same
    # list and opened it a level at a time, one request each, and then fetched
    # the panel twice on top of that.
    my $tree = template 'ajax/device/snmptree.tt',
      { device => $device,
        nodes  => _get_snmp_data($device, '.1', \@results) },
      { layout => 'noop' };

    # The panel for the hit rides along out of band, so choosing a search result
    # costs nothing beyond the tree it opened.
    my $icon = _snmp_state_icon('far fa-circle fa-lg text-success');
    my $stash = _snmp_node_stash($device, $results[-1]);
    return $tree . $icon unless $stash;

    my $detail = template 'ajax/device/snmpnode.tt', $stash, { layout => 'noop' };
    return $tree .'<div id="node" hx-swap-oob="true">'. $detail .'</div>'. $icon;
};

get '/ajax/content/device/:ip/snmpnode/:oid' => require_login sub {
    my $device = try { schema(vars->{'tenant'})->resultset('Device')
                                         ->find( param('ip') ) }
       or send_error('Bad Device', 404);

    my $oid = param('oid');
    $oid =~ m/^\.1(\.\d+)*$/ or send_error('Bad OID', 404);

    my $stash = _snmp_node_stash($device->ip, $oid, param('munge'))
      or send_error('Bad OID', 404);

    content_type 'text/html';
    template 'ajax/device/snmpnode.tt', $stash, { layout => 'noop' };
};

# Everything the detail panel needs for one node. The search route renders the
# same panel for its hit, so this lives apart from the route that serves it.
sub _snmp_node_stash {
    my ($ip, $oid, $munge) = @_;

    my $object = schema(vars->{'tenant'})->resultset('SNMPObject')
      ->find({'me.oid' => $oid},
               {join => ['snmp_filter'], prefetch => ['snmp_filter']})
      or return undef;

    $munge ||= ($object->snmp_filter ? $object->snmp_filter->subname : undef);

    # this is a bit lazy, could be a join on above with some effort
    my $value = schema(vars->{'tenant'})->resultset('DeviceBrowser')
      ->search({-and => [-bool => \q{ array_length(oid_parts, 1) IS NOT NULL },
                         -bool => \q{ jsonb_typeof(value) = 'array' }]})
      ->find({'me.oid' => $oid, 'me.ip' => $ip});

    my %data = (
      $object->get_columns,
      snmp_object => { $object->get_columns },
      value => ( defined $value ? decode_and_munge( $munge, $value->value ) : undef ),
    );

    my @mungers = schema(vars->{'tenant'})->resultset('SNMPFilter')
                                          ->search({},{ distinct => 1, order_by => 'subname' })
                                          ->get_column('subname')->all;

    return { node => \%data, munge => $munge, mungers => \@mungers,
             device => $ip, oid => $oid };
}

sub _get_snmp_data {
    my ($ip, $base, $open_to) = @_;
    my @parts = grep {length} split m/\./, $base;
    my %open = map {($_ => 1)} @{ $open_to || [] };

    # Only a search passes a path, and its last step is the node that matched.
    my $hit = (scalar @{ $open_to || [] }) ? $open_to->[-1] : '';

    my %meta = map { ('.'. join '.', @{$_->{oid_parts}}) => $_ }
               schema(vars->{'tenant'})->resultset('Virtual::FilteredSNMPObject')
                                 ->search({}, { bind => [
                                     $ip,
                                     (scalar @parts + 1),
                                     (scalar @parts + 1),
                                     $base,
                                 ] })->hri->all;

    my @items = map {
        my $oid = $_;
        my $row = $meta{$oid};
        my $has_children = ($row->{num_children} ? 1 : 0);

        # Open a node the search asked for, and keep the older rule that a node
        # with data and a single child opens itself so the child is not hidden
        # behind one more click.
        my $open = ($has_children and ($open{$oid}
                     or ($row->{browser} and $row->{num_children} == 1))) ? 1 : 0;

        {
          oid   => $oid,
          label => ($row->{leaf} .' ('. $row->{oid_parts}->[-1] .')'),
          icon  => _snmp_icon($row),
          has_children => $has_children,
          found => (($hit and $oid eq $hit) ? 1 : 0),
          open  => $open,
          children => ($open ? _get_snmp_data($ip, $oid, $open_to) : []),
        }
      } sort {$meta{$a}->{oid_parts}->[-1] <=> $meta{$b}->{oid_parts}->[-1]} keys %meta;

    return \@items;
}

# A folder unless the row is a table or a leaf, and muted unless this device
# has a value for it.
sub _snmp_icon {
    my $row = shift;
    my $lit = ($row->{browser} ? ' text-info' : ' text-muted');

    return 'fas fa-table-cells'. $lit if scalar @{ $row->{index} };

    return 'fas fa-leaf'. $lit
      if $row->{num_children} == 0
         and ($row->{type} or $row->{access} =~ m/^(?:read|write)/
              or $row->{oid_parts}->[-1] == 0);

    return $row->{browser} ? 'fas fa-folder text-info' : 'far fa-folder text-muted';
}

true;
