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
use Module::Load ();
use Try::Tiny;

register_device_tab({ tag => 'snmp', label => 'SNMP' });

get '/ajax/content/device/snmp' => require_login sub {
    my $device = try { schema(vars->{'tenant'})->resultset('Device')
                                   ->search_for_device( param('q') ) }
       or send_error('Bad Device', 404);

    template 'ajax/device/snmp.tt', { device => $device->ip },
      { layout => 'noop' };
};

ajax '/ajax/data/device/:ip/snmptree/:base' => require_login sub {
    my $device = try { schema(vars->{'tenant'})->resultset('Device')
                                         ->find( param('ip') ) }
       or send_error('Bad Device', 404);

    my $base = param('base');
    $base =~ m/^\.1(\.\d+)*$/ or send_error('Bad OID Base', 404);

    content_type 'application/json';

    return to_json [{
      text => 'No data for this device. Admins can request a snapshot in the Details tab.',
      children => \0,
      state => { disabled => \1 },
      icon => 'icon-search',
    }] unless $device->oids->count;

    # snapshot should run a loadmibs, but just in case that didn't happen...
    return to_json [{
      text => 'No MIB objects. Please run a loadmibs job.',
      children => \0,
      state => { disabled => \1 },
      icon => 'icon-search',
    }] unless schema(vars->{'tenant'})->resultset('SNMPObject')->count();

    my $items = _get_snmp_data($device->ip, $base);
    to_json $items;
};

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

ajax '/ajax/data/snmp/nodesearch' => require_login sub {
    my $to_match = param('str') or return to_json [];
    my $partial = param('partial');
    my $device = param('ip');
    my $deviceonly = param('deviceonly');

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
    return to_json [] unless $found;

    $found = $found->oid;
    $found =~ s/^\.1\.?//;
    my @results = ('.1');

    foreach my $part (split m/\./, $found) {
        my $last = $results[-1];
        push @results, "${last}.${part}";
    }

    content_type 'application/json';
    to_json \@results;
};

ajax '/ajax/content/device/:ip/snmpnode/:oid' => require_login sub {
    my $device = try { schema(vars->{'tenant'})->resultset('Device')
                                         ->find( param('ip') ) }
       or send_error('Bad Device', 404);

    my $oid = param('oid');
    $oid =~ m/^\.1(\.\d+)*$/ or send_error('Bad OID', 404);

    my $object = schema(vars->{'tenant'})->resultset('SNMPObject')
      ->find({'me.oid' => $oid},
               {join => ['snmp_filter'], prefetch => ['snmp_filter']})
      or send_error('Bad OID', 404);

    my $munge = (param('munge') ||
                 ($object->snmp_filter ? $object->snmp_filter->subname : undef));

    # this is a bit lazy, could be a join on above with some effort
    my $value = schema(vars->{'tenant'})->resultset('DeviceBrowser')
      ->search({-and => [-bool => \q{ array_length(oid_parts, 1) IS NOT NULL },
                         -bool => \q{ jsonb_typeof(value) = 'array' }]})
      ->find({'me.oid' => $oid, 'me.ip' => $device});

    my %data = (
      $object->get_columns,
      snmp_object => { $object->get_columns },
      value => ( defined $value ? decode_and_munge( $munge, $value->value ) : undef ),
    );

    my @mungers = schema(vars->{'tenant'})->resultset('SNMPFilter')
                                          ->search({},{ distinct => 1, order_by => 'subname' })
                                          ->get_column('subname')->all;

    template 'ajax/device/snmpnode.tt',
        { node => \%data, munge => $munge, mungers => \@mungers },
        { layout => 'noop' };
};

sub _get_snmp_data {
    my ($ip, $base, $recurse) = @_;
    my @parts = grep {length} split m/\./, $base;

    my %meta = map { ('.'. join '.', @{$_->{oid_parts}}) => $_ }
               schema(vars->{'tenant'})->resultset('Virtual::FilteredSNMPObject')
                                 ->search({}, { bind => [
                                     $ip,
                                     (scalar @parts + 1),
                                     (scalar @parts + 1),
                                     $base,
                                 ] })->hri->all;

    my @items = map {{
        id => $_,
        mib  => $meta{$_}->{mib},  # accessed via node.original.mib
        leaf => $meta{$_}->{leaf}, # accessed via node.original.leaf
        text => ($meta{$_}->{leaf} .' ('. $meta{$_}->{oid_parts}->[-1] .')'),
        has_value => $meta{$_}->{browser},

        ($meta{$_}->{browser} ? (icon => 'icon-folder-close text-info')
                              : (icon => 'icon-folder-close-alt muted')),

        (scalar @{$meta{$_}->{index}}
          ? (icon => 'icon-th'.($meta{$_}->{browser} ? ' text-info' : ' muted')) : ()),

        (($meta{$_}->{num_children} == 0 and ($meta{$_}->{type}
                                              or $meta{$_}->{access} =~ m/^(?:read|write)/
                                              or $meta{$_}->{oid_parts}->[-1] == 0))
          ? (icon => 'icon-leaf'.($meta{$_}->{browser} ? ' text-info' : ' muted')) : ()),

        # jstree will async call to expand these, and while it's possible
        # for us to prefetch by calling _get_snmp_data() and passing to
        # children, it's much slower UX. async is better for search especially
        children => ($meta{$_}->{num_children} ? \1 : \0),
  
        # and set the display to open to show the single child
        # but only if there is data below
        state => { opened => (($meta{$_}->{browser} and $meta{$_}->{num_children} == 1) ? \1 : \0 ) },

      }} sort {$meta{$a}->{oid_parts}->[-1] <=> $meta{$b}->{oid_parts}->[-1]} keys %meta;

    return \@items;
}

true;
