#!/usr/bin/env perl

# The Ports tab's rows reach the browser as JSON from /ajax/data/device/ports,
# and netdisco-ports.js draws the cells ports.tt used to. The route itself is
# require_login and cannot be driven from here (see xt/36), so this drives
# the builders it is made of, which are kept free of param(), setting() and
# the session for that reason: the column list, one port's hash, one node's
# hash, the shared meta block, and the plugin cells ports_cells.tt still
# draws in Template Toolkit.
#
# The port hashes are built from the same eight rows the ports.tt snapshot
# used (xt/lib/Test/Netdisco/Snapshot.pm), one per icon state, and are
# committed as xt/ports-fixture.json for xt/js/ports-table.test.js to draw.

use strict;
use warnings;

use Test::More 0.88;
use File::Temp 'tempdir';
use File::Path 'make_path';
use JSON::PP ();
use lib 'xt/lib';

use Template::AutoFilter;
use Test::Netdisco::PortsJSON
  qw/fake_row fixture_payload fixture_json FIXTURE_FILE PORT_COLUMNS/;

require App::Netdisco::Web::Plugin::Device::Ports;
require App::Netdisco::Util::Permission;

my $P = 'App::Netdisco::Web::Plugin::Device::Ports';
my $columns = $P->can('_port_columns');
my $port_json = $P->can('_port_json');
my $node_json = $P->can('_node_json');

sub names { [ map { $_->{name} } @{ $_[0] } ] }

subtest '_port_columns' => sub {
    my %all = map {( $_->{name} => 1 )} @{ PORT_COLUMNS() };

    is_deeply names($columns->({ c_port => 1, c_name => 1 }, PORT_COLUMNS, 1)),
      [qw/c_port c_name/], 'only the columns asked for, in config order';

    ok !(grep { $_ eq 'c_admin' } @{ names($columns->(\%all, PORT_COLUMNS, 1)) }),
      'c_admin is a mode, never a column';

    ok !(grep { $_ eq 'c_links' } @{ names($columns->(\%all, PORT_COLUMNS, 0)) }),
      'c_links is left out without external links configured';
    ok((grep { $_ eq 'c_links' } @{ names($columns->(\%all, PORT_COLUMNS, 1)) }),
      'and kept with some');

    my $both = $columns->(\%all, PORT_COLUMNS, 1);
    ok !(grep { $_->{name} eq 'c_nodes' } @$both),
      'c_nodes folds into c_neighbors when both are on';
    my ($n) = grep { $_->{name} eq 'c_neighbors' } @$both;
    is $n->{label}, 'Connected Nodes & Devices', 'under the shared label';

    my $nodes_only = $columns->({ c_nodes => 1 }, PORT_COLUMNS, 1);
    is_deeply [ map { $_->{label} } @$nodes_only ], ['Connected Nodes'],
      'c_nodes alone keeps its own column and label';
    my $neighbors_only = $columns->({ c_neighbors => 1 }, PORT_COLUMNS, 1);
    is_deeply [ map { $_->{label} } @$neighbors_only ], ['Connected Devices'],
      'c_neighbors alone is Connected Devices';

    my @with_plugin = (@{ PORT_COLUMNS() },
      { name => 'shown', label => 'Shown' },
      { name => 'gone', label => 'Gone', hidden => 1 });
    is_deeply names($columns->({ shown => 1, gone => 1 }, \@with_plugin, 0)),
      ['shown'], 'a plugin column marked hidden is left out, as its cells were';
};

my $payload = fixture_payload();
my %row = map {( $_->{port} => $_ )} @{ $payload->{rows} };

subtest '_port_json on the snapshot rows' => sub {
    is scalar @{ $payload->{rows} }, 8, 'one hash per fixture row';

    is $row{'Gi1/2'}->{up_admin}, 'down', 'admin-down state';
    is $row{'Gi1/3'}->{stp}, 'blocking', 'STP blocking state';
    is $row{'Gi1/3'}->{vlan_count}, 1, 'with the VLAN count the icon tests';
    is $row{'Gi1/4'}->{error_disable_cause}, 'err-disable', 'error-disabled state';
    is $row{'Gi1/5'}->{is_free}, 1, 'free, from has_column_loaded and is_free';
    ok !exists $row{'Gi1/6'}->{vlans},
      'a port over devport_vlan_limit gets its count but no list';
    is $row{'Gi1/6'}->{vlan_count}, 99, 'the count it says is too many';
    is_deeply $row{'Gi1/9'}->{vlans}, [10, 20], 'a listable membership';
    is_deeply $row{'Gi1/9'}->{power}, { admin => 'true', power => 5 }, 'PoE';
    is_deeply $row{'Gi1/1'}->{ssids}, ['CORP', 'GUEST'], 'SSIDs';
    is_deeply $row{'Gi1/1'}->{tags}, ['core'], 'tags';
    is $row{'Gi1/1'}->{slave_of}, 1, 'LAG member';
    is_deeply [ @{ $row{'Gi1/1'} }{qw/acl_service acl_name acl_pvid/} ], [1, 1, 1],
      'port control ACLs under c_admin';
    ok !exists $row{'Gi1/2'}->{acl_pvid}, 'and only the ones granted';
    is $row{'Gi1/4'}->{has_group}, 1, 'subinterface group parent';
    is $row{'Gi1/10'}->{only_dot_zero}, 1, 'dot-zero-only parent';

    is $row{'Gi1/1'}->{search}, 'aa:bb:cc:00:01:01 192.0.2.10 host.example.com',
      'the search shadow goes out as search, the old data-search';
    is $row{'Gi1/1'}->{node_count}, 2, 'node_count under c_nodes';
    is $row{'Gi1/2'}->{node_count}, 0, 'zero rather than absent';

    ok !(grep { exists $_->{descr} } @{ $payload->{rows} }),
      'empty values are left out';
    ok !(grep { exists $_->{nodes_search} or exists $_->{port_acl_name} }
         @{ $payload->{rows} }), 'the route\'s own decoration keys are not sent';

    my $off = $port_json->(fake_row({ port => 'x', up => 'up',
      port_comment => 'c', port_ssids => ['a'], port_power => { admin => 'true' },
      node_count => 3, nodes_search => 's', port_acl_service => 1 }),
      { p => {} });
    is_deeply $off, { port => 'x', up => 'up' },
      'column data goes out only under the column that draws it';
};

subtest 'xt/ports-fixture.json is current' => sub {
    open my $fh, '<:raw', FIXTURE_FILE or die FIXTURE_FILE . ": $!";
    my $committed = do { local $/; <$fh> };
    ok $committed eq fixture_json(), FIXTURE_FILE . ' matches the builders'
      or diag 'run xt/bin/regenerate-ports-fixture and review the diff';
};

subtest '_node_json' => sub {
    my $node = { mac => 'x', net_mac => undef, vlan => '10', active => 0,
      time_last_age => '1 day',
      stitched_ips => [ { ip => '10.0.0.1', dns => 'a', active => 1 },
                        { ip => '10.0.0.2', dns => '', active => 0 } ],
      wireless => [ { ssid => 'CORP' } ],
      manufacturer => [ { abbrev => 'Acme' } ],
      netbios => [ { domain => 'D', nbname => 'N', nbuser => undef, ip => '10.0.0.1' } ] };
    require NetAddr::MAC;
    $node->{net_mac} = NetAddr::MAC->new(mac => '00:11:22:33:44:55');

    my $none = $node_json->($node, undef, { p => {}, mac_format_call => 'as_cisco' });
    is_deeply $none, { mac => '0011.2233.4455', vlan => '10', archived => 1 },
      'without n_* options: the MAC in the chosen format, VLAN, archived';

    my $all = $node_json->($node, '10.0.0.2', { p => { map {( $_ => 1 )}
      qw/n_ip4 n_age n_ssid n_vendor n_netbios/ } });
    is $all->{mac}, '00:11:22:33:44:55', 'IEEE when no format is given';
    is $all->{neighbor}, 1, 'the node behind remote_ip is marked, not dropped';
    is_deeply $all->{ips}, [ { ip => '10.0.0.1', dns => 'a' },
      { ip => '10.0.0.2', archived => 1 } ], 'IPs, archived ones marked';
    is $all->{age}, '1 day', 'age';
    is_deeply $all->{ssids}, ['CORP'], 'SSIDs';
    is $all->{vendor}, 'Acme', 'vendor';
    is $all->{netbios}->[0]->{nbname}, 'N', 'NetBIOS';
};

subtest 'node_params and meta' => sub {
    my $meta = $P->can('_port_meta')->({
      device => '10.0.0.1', p => { p_vlan_names => 1 },
      vlans => { 'Gi1/1' => { vlan_set => [10, 20], vlan_name_set => ['ten', undef] } },
      extra_cols => [ { name => 'x', field => 'cf_x', editable => 1, renderer => 'xr',
                        json => sub {} } ],
      node_params => $P->can('_deferred_node_params')->(1, 0, 1, 0, 0, 0, 0, 1, 'Cisco'),
    });
    is $meta->{node_params}, '&n_ip4=1&n_dns=1&n_archived=1&mac_format=Cisco',
      'node_params is the querystring the inline nodes were drawn with';
    is_deeply $meta->{vlan_names}, { 10 => 'ten', 20 => '' },
      'VLAN names once per device, under p_vlan_names';
    is_deeply $meta->{extra}, { x => { field => 'cf_x', editable => 1, renderer => 'xr' } },
      'a plugin column\'s config, without its json coderef';
};

# ports_cells.tt with two plugin templates, one of which dies, rendered as
# the route does: every cell handed back through collect().
my $dir = tempdir(CLEANUP => 1);
make_path("$dir/plugin/$_") for qw/good broken/;
{
    open my $fh, '>', "$dir/plugin/good/device_port_column.tt" or die $!;
    print {$fh} qq{<b>[% row.port %] on [% device.ip %] &amp; [% config.name %]</b>\n};
    open $fh, '>', "$dir/plugin/broken/device_port_column.tt" or die $!;
    print {$fh} qq{before [% THROW oops 'no' %]\n};
}

my %cells = ();
my $tt = Template::AutoFilter->new({
  INCLUDE_PATH => [ $dir, 'share/views' ],
  ANYCASE => 1, PRE_CHOMP => 1, AUTO_FILTER => 'html_entity',
});
my @rows = map { fake_row({ port => $_, up => 'up' }) } qw/Gi1 Gi2/;
my @cols = ({ name => 'good', field => 'cf_good', no => ['port:Gi2'] },
            { name => 'broken', field => 'cf_broken' });
my $out = '';
$tt->process('ajax/device/ports_cells.tt', {
  results => \@rows, device => { ip => '10.0.0.1' },
  want_links => 0, cell_cols => \@cols,
  permitted_by_acl => \&App::Netdisco::Util::Permission::permitted_by_acl,
  collect => sub { my ($port, $name, $html) = @_;
                   $html =~ s/^\s+|\s+$//g; $cells{$port}->{$name} = $html; '' },
}, \$out) or die $tt->error;

subtest 'plugin cells' => sub {
    like $out, qr/\A\s*\z/, 'ports_cells.tt itself outputs nothing';
    is $cells{Gi1}->{good}, '<b>Gi1 on 10.0.0.1 &amp; good</b>',
      'a plugin template is rendered with row, device and config';
    ok !exists $cells{Gi2}->{good}, 'not for a row its ACL refuses';
    ok !exists $cells{Gi1}->{broken}, 'a template that dies leaves no cell';

    my $opt = { p => { good => 1, broken => 1 }, extra_cols => \@cols,
                cells => \%cells };
    my $gi1 = $port_json->(fake_row({ port => 'Gi1', cf_good => 'g', cf_broken => 'b' }), $opt);
    my $gi2 = $port_json->(fake_row({ port => 'Gi2', cf_good => 'g', cf_broken => 'b' }), $opt);

    is $gi1->{cells}->{good}, $cells{Gi1}->{good}, 'a rendered cell goes out as cells';
    ok !exists $gi1->{fields}->{cf_good}, 'without its raw field';
    is $gi1->{fields}->{cf_broken}, 'b',
      'a failed cell goes out as its field, which the browser draws';
    is_deeply $gi2->{hidden_cells}, { good => 1 }, 'an ACL-refused cell is hidden';
    ok !exists $gi2->{fields}->{cf_good}, 'and its value is not sent';

    my $js = { name => 'js', field => 'cf_js', renderer => 'demo',
               json => sub { my ($row, $device) = @_; { p => $row->port, d => $device } } };
    my $r = $port_json->(fake_row({ port => 'Gi1', cf_js => 'v' }),
      { p => {}, extra_cols => [$js], device => 'dev' });
    is $r->{fields}->{cf_js}, 'v', 'a JS-rendered column gets its field';
    is_deeply $r->{data}->{js}, { p => 'Gi1', d => 'dev' },
      'and the json coderef\'s data, given the row and the device';
};

# A site's own ajax/device/ports.tt from before the rows came as JSON draws
# them itself, and has to go on getting the rows it expects rather than a
# frame it would render as an empty table. It is told apart by the loader the
# current template names, so a site's copy of the current one is not
# mistaken for it. The shipped template has to count as current, whichever
# of the engine's paths it resolves from.
subtest 'a site\'s own ports template' => sub {
    my $legacy = \&App::Netdisco::Web::Plugin::Device::Ports::_ports_template_is_legacy;

    ok $legacy->("<table>[% FOREACH row IN results %]<tr>[% row.port %]</tr>[% END %]</table>"),
      'a template that draws the rows itself is the old kind';
    ok $legacy->(''), 'an empty one is too';
    ok $legacy->(undef), 'and one that could not be read';

    my $shipped = do {
        open my $fh, '<', 'share/views/ajax/device/ports.tt' or die $!;
        local $/; <$fh>;
    };
    ok !$legacy->($shipped), 'the shipped template is current';
    (my $site_copy = $shipped) =~ s/^/[%# a site's edit %]\n/;
    ok !$legacy->($site_copy), 'and so is a site\'s copy of it';
    ok $legacy->($shipped =~ s/data-nd-loader=/data-nd-other=/r),
      'a copy that lost the loader is the old kind';
};

done_testing;
