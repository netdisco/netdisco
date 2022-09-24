package App::Netdisco::Web::Plugin::Device::SNMP;

use strict;
use warnings;

use Dancer qw(:syntax);
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Swagger;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::SNMP qw(%ALL_MUNGERS decode_and_munge);
use Module::Load ();
use Try::Tiny;

register_device_tab({ tag => 'snmp', label => 'SNMP',
  render_if => sub { schema(vars->{'tenant'})->resultset('DeviceBrowser')->count() } });

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
      text => 'No data for this device. You can request a snapshot in the Details tab.',
      children => \0,
      state => { disabled => \1 },
      icon => 'icon-search',
    }] unless schema(vars->{'tenant'})->resultset('DeviceSnapshot')->find($device->ip);

    return to_json [{
      text => 'No MIB data. Please run `~/bin/netdisco-do loadmibs`.',
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
    my $table = ($deviceonly ? 'DeviceBrowser' : 'SNMPObject');

    my @found = schema(vars->{'tenant'})->resultset($table)
      ->search({ -or => [ oid => $term,
                          oid => { -like => ($term .'.%') },
                          leaf => { -ilike => ('%'. $term .'%') } ],
                 (($deviceonly and $device) ? (ip => $device) : ()), },
               { rows => 25, columns => 'leaf', order_by => 'oid_parts' })
      ->get_column('leaf')->all;
    return to_json [] unless scalar @found;

    content_type 'application/json';
    to_json [ sort @found ];
};

ajax '/ajax/data/snmp/nodesearch' => require_login sub {
    my $to_match = param('str') or return to_json [];
    my $partial = param('partial');

    my $found = undef;
    if ($partial) {
        $found = schema(vars->{'tenant'})->resultset('SNMPObject')
          ->search({ -or => [ oid => $to_match,
                              oid => { -like => ($to_match .'.%') },
                              leaf => { -ilike => ($to_match .'%') } ] },
                   { rows => 1, order_by => 'oid_parts' })->first;
    }
    else {
        $found = schema(vars->{'tenant'})->resultset('SNMPObject')
          ->search({ -or => [ oid => $to_match,
                              leaf => $to_match ] },
                   { rows => 1, order_by => 'oid_parts' })->first;
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

    my $object = schema(vars->{'tenant'})->resultset('DeviceBrowser')
      ->with_snmp_object($device->ip)->find({ 'snmp_object.oid' => $oid })
      or send_error('Bad OID', 404);

    my $munge = (param('munge') and exists $ALL_MUNGERS{param('munge')})
      ? param('munge') : $object->munge;

    my %data = (
      $object->get_columns,
      snmp_object => { $object->snmp_object->get_columns },
      value => decode_and_munge( $munge, $object->value ),
    );

    template 'ajax/device/snmpnode.tt',
        { node => \%data, munge => $munge, mungers => [sort keys %ALL_MUNGERS] },
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
        text => ($meta{$_}->{leaf} .' ('. $meta{$_}->{oid_parts}->[-1] .')'),

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
