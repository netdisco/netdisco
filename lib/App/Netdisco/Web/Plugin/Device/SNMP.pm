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
                                         ->find( param('q') ) }
       or send_error('Bad Device', 404);

    template 'ajax/device/snmp.tt', { device => $device->ip },
      { layout => 'noop' };
};

ajax '/ajax/data/device/:ip/snmptree/:base' => require_login sub {
    my $device = try { schema('netdisco')->resultset('Device')
                                         ->find( param('ip') ) }
       or send_error('Bad Device', 404);

    my $recurse =  ((param('recurse') and param('recurse') eq 'on') ? 0 : 1);
    my $base = param('base');
    $base =~ m/^\.1\.3\.6\.1(\.\d+)*$/ or send_error('Bad OID Base', 404);

    my $items = _get_snmp_data($device->ip, $base, $recurse);

    content_type 'application/json';
    to_json $items;
};

ajax '/ajax/data/device/:ip/typeahead' => require_login sub {
    my $device = try { schema('netdisco')->resultset('Device')
                                         ->find( param('ip') ) }
       or send_error('Bad Device', 404);

    my $term = param('term') or return to_json [];
    $term = '%'. $term .'%';

    my @found = schema('netdisco')->resultset('DeviceBrowser')
      ->search({ leaf => { -ilike => $term }, ip => $device->ip },
               { rows => 25, columns => 'leaf' })
      ->get_column('leaf')->all;
    return to_json [] unless scalar @found;

    content_type 'application/json';
    to_json [ sort @found ];
};

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
    $found = schema('netdisco')->resultset('DeviceBrowser')
      ->search({ -or => [ oid => { $op => $to_match }, leaf => { $op => $to_match } ], ip => $device->ip },
               { rows => 1, order_by => 'oid_parts' })->first;

    return to_json [] unless $found;

    $found = $found->oid;
    $found =~ s/^\.1\.3\.6\.1\.?//;
    my @results = ('.1.3.6.1');

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
    $oid =~ m/^\.1\.3\.6\.1(\.\d+)*$/ or send_error('Bad OID', 404);

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
    ++$recurse;

    my %kids = map { ($base .'.'. $_->{part}) => $_ }
               schema('netdisco')->resultset('Virtual::OidChildren')
                                 ->search({}, { bind => [
                                     (scalar @parts + 1),
                                     (scalar @parts + 2),
                                     $base,
                                     (scalar @parts + 1),
                                     (scalar @parts + 1),
                                     $ip,
                                     $base,
                                 ] })->hri->all;

    return [{
      text => 'No SNMP data for this device.',
      children => \0,
      state => { disabled => \1 },
      icon => 'icon-search',
    }] unless scalar keys %kids;

    my %meta = map { ('.'. join '.', @{$_->{oid_parts}}) => $_ }
               schema('netdisco')->resultset('Virtual::FilteredSNMPObject')
                                 ->search({}, { bind => [
                                     $base,
                                     (scalar @parts + 1),
                                     [[ map {$_->{part}} values %kids ]],
                                     (scalar @parts + 1),
                                 ] })->hri->all;

    my @items = map {{
        id => $_,
        text => ($meta{$_}->{leaf} .' ('. $kids{$_}->{part} .')'),

        # for nodes with only one child, recurse to prefetch...
        children => ( ($recurse < 2 and $kids{$_}->{children} == 1)
          ? _get_snmp_data($ip, ("${base}.". $kids{$_}->{part}), $recurse)
          : ($kids{$_}->{children} ? \1 : \0)),

        # and set the display to open to show the single child
        state => { opened => ( ($recurse < 2 and $kids{$_}->{children} == 1)
          ? \1
          : \0 ) },

        ($kids{$_}->{children} ? () : (icon => 'icon-leaf')),
        (scalar @{$meta{$_}->{index}} ? (icon => 'icon-th') : ()),
      }} sort {$kids{$a}->{part} <=> $kids{$b}->{part}} keys %kids;

    return \@items;
}

true;
