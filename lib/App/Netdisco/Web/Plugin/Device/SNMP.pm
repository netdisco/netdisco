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
  render_if => sub { schema('netdisco')->resultset('DeviceBrowser')->count() } });

get '/ajax/content/device/snmp' => require_login sub {
    my $device = try { schema('netdisco')->resultset('Device')
                                   ->search_for_device( param('q') ) }
       or send_error('Bad Device', 404);

    template 'ajax/device/snmp.tt', { device => $device->ip },
      { layout => 'noop' };
};

ajax '/ajax/data/device/:ip/snmptree/:base' => require_login sub {
    my $device = try { schema('netdisco')->resultset('Device')
                                         ->find( param('ip') ) }
       or send_error('Bad Device', 404);

    my $base = param('base');
    $base =~ m/^\.1(\.\d+)*$/ or send_error('Bad OID Base', 404);

    my $items = _get_snmp_data($device->ip, $base);

    content_type 'application/json';
    to_json $items;
};

# TODO add form option for limiting to this device, so leave :ip
ajax '/ajax/data/device/:ip/typeahead' => require_login sub {
    my $device = try { schema('netdisco')->resultset('Device')
                                         ->find( param('ip') ) }
       or send_error('Bad Device', 404);

    my $term = param('term') or return to_json [];
    $term = '%'. $term .'%';

    my @found = schema('netdisco')->resultset('SNMPObject')
      ->search({ leaf => { -ilike => $term } },
               { rows => 25, columns => 'leaf' })
      ->get_column('leaf')->all;
    return to_json [] unless scalar @found;

    content_type 'application/json';
    to_json [ sort @found ];
};

# TODO add form option for limiting to this device, so leave :ip
ajax '/ajax/data/device/:ip/snmpnodesearch' => require_login sub {
    my $device = try { schema('netdisco')->resultset('Device')
                                         ->find( param('ip') ) }
       or send_error('Bad Device', 404);

    my $to_match = param('str');
    my $partial = param('partial');
    my $excludeself = param('excludeself');

    return to_json [] unless $to_match or length($to_match);
    $to_match = $to_match . '%' if $partial;
    my $found = undef;

    my $op = ($partial ? '-ilike' : '=');
    $found = schema('netdisco')->resultset('SNMPObject')
      ->search({ -or => [ oid => { $op => $to_match }, leaf => { $op => $to_match } ] },
               { rows => 1, order_by => 'oid_parts' })->first;

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
    my $device = try { schema('netdisco')->resultset('Device')
                                         ->find( param('ip') ) }
       or send_error('Bad Device', 404);

    my $oid = param('oid');
    $oid =~ m/^\.1(\.\d+)*$/ or send_error('Bad OID', 404);

    my $object = schema('netdisco')->resultset('DeviceBrowser')
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

    return [{
      text => 'No data for this device. You can request a snapshot in the Details tab.',
      children => \0,
      state => { disabled => \1 },
      icon => 'icon-search',
    }] unless schema('netdisco')->resultset('DeviceSnapshot')->find($ip);

    my %meta = map { ('.'. join '.', @{$_->{oid_parts}}) => $_ }
               schema('netdisco')->resultset('Virtual::FilteredSNMPObject')
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

        (($meta{$_}->{num_children} == 0 and ($meta{$_}->{access} =~ m/^(?:read|write)/ or $meta{$_}->{oid_parts}->[-1] == 0))
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
