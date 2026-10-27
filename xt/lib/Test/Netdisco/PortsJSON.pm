package Test::Netdisco::PortsJSON;

use strict;
use warnings;

use JSON::PP ();
use Test::Netdisco::Snapshot 'ports_fixture';

use base 'Exporter';
our @EXPORT_OK = qw/fake_row fixture_payload fixture_json FIXTURE_FILE
                    PORT_COLUMNS/;

=head1 NAME

Test::Netdisco::PortsJSON - the Ports tab's JSON, built from the snapshot rows

=head1 DESCRIPTION

F<xt/lib/Test/Netdisco/Snapshot.pm>'s eight Ports fixture rows, sent through
the same builders the C</ajax/data/device/ports> route uses. The result is
committed as F<xt/ports-fixture.json>, which F<xt/js/ports-table.test.js>
draws, so the Perl and JavaScript halves of the table are tested on the same
ports. F<xt/179-ports-json.t> fails when the file is stale; rewrite it with
F<xt/bin/regenerate-ports-fixture> and review the diff.

=cut

use constant FIXTURE_FILE => 'xt/ports-fixture.json';

# share/config.yml's sidebar_defaults.device_ports, in idx order, as Web.pm
# builds settings.port_columns from it. If that block changes, change this.
use constant PORT_COLUMNS => [
  map {{ name => $_->[0], label => $_->[1] }} (
    [c_admin => 'Port Control and Editing'], [c_port => 'Port'],
    [c_descr => 'Description'], [c_comment => 'Last Comment'],
    [c_type => 'Type'], [c_ifindex => 'Interface Index'],
    [c_lastchange => 'Last Change'], [c_name => 'Name'], [c_tags => 'Tags'],
    [c_links => 'External Links'], [c_speed_admin => 'Speed (configured)'],
    [c_speed => 'Speed (running)'], [c_duplex_admin => 'Duplex (configured)'],
    [c_duplex => 'Duplex (running)'], [c_error => 'Error Message'],
    [c_mac => 'Port MAC'], [c_mtu => 'MTU'], [c_pvid => 'Native VLAN'],
    [c_vmember => 'VLAN Membership'], [c_power => 'PoE'], [c_ssid => 'SSID'],
    [c_nac_summary => 'NAC/802.1X Status'], [c_nodes => 'Connected Nodes'],
    [c_neighbors => 'Connected Devices'], [c_stp => 'Spanning Tree'],
    [c_up => 'Up/Down Status'],
  )
];

{
    # The snapshot rows are plain hashes; this gives them the few
    # DBIx::Class::Row methods _port_json calls. get_columns is every plain
    # value, which also carries the route's decorations: _port_json reads
    # only named columns, so they do no harm.
    package Test::Netdisco::PortsJSON::Row;
    sub new { my ($class, $h) = @_; return bless { %$h }, $class }
    sub port { return $_[0]->{port} }
    sub get_column { return $_[0]->{ $_[1] } }
    sub get_columns {
        my $self = shift;
        return map {( $_ => $self->{$_} )} grep { not ref $self->{$_} } keys %$self;
    }
    sub has_column_loaded {
        my ($self, $col) = @_;
        return $self->{has_column_loaded}->($col)
          if ref $self->{has_column_loaded} eq 'CODE';
        return exists $self->{$col};
    }
    sub remote_inventory { return $_[0]->{remote_inventory} }
    sub remote_ip { return $_[0]->{remote_ip} }
    sub tags { return $_[0]->{tags} }

    # the fixture's net_mac is { as_string => '...' }, standing for the
    # NetAddr::MAC object whose mac_format_call method the template calls
    package Test::Netdisco::PortsJSON::MAC;
    sub new { my ($class, $h) = @_; return bless { %$h }, $class }
    sub as_string { return $_[0]->{as_string} }
}

sub fake_row { return Test::Netdisco::PortsJSON::Row->new(@_) }

sub _with_mac_objects {
    my ($row) = @_;
    my %r = %$row;
    $r{stitched_nodes} = [ map {{
      %$_, net_mac => Test::Netdisco::PortsJSON::MAC->new($_->{net_mac}),
    }} @{ $row->{stitched_nodes} } ] if $row->{stitched_nodes};
    return \%r;
}

=head2 fixture_payload

The C<{ columns, rows, meta }> the route would send for the fixture rows.

=cut

sub fixture_payload {
    require App::Netdisco::Web::Plugin::Device::Ports;
    my $f = ports_fixture();
    my %p = map {( $_ => ($f->{params}->{$_} ? 1 : 0) )} keys %{ $f->{params} };

    my $opt = {
      p => \%p,
      mac_format_call => $f->{mac_format_call},
      domain_suffix => qr//,
      vlans => $f->{vlans},
      vlan_limit => $f->{settings}->{devport_vlan_limit},
      extra_cols => [],
      cells => {},
    };

    return {
      columns => App::Netdisco::Web::Plugin::Device::Ports::_port_columns(
        \%p, PORT_COLUMNS, 0),
      rows => [ map {
        App::Netdisco::Web::Plugin::Device::Ports::_port_json(
          fake_row(_with_mac_objects($_)), $opt)
      } @{ $f->{results} } ],
      meta => App::Netdisco::Web::Plugin::Device::Ports::_port_meta({
        device => '', q => '', p => \%p, only_free => 0,
        settings => $f->{settings}, vlans => $f->{vlans},
        extra_cols => [], node_params => '',
        port_columns => PORT_COLUMNS, has_ext_links => 0,
      }),
    };
}

=head2 fixture_json

C<fixture_payload> as the committed file holds it: canonical, so a rewrite
only shows what changed.

=cut

sub fixture_json {
    return JSON::PP->new->canonical->pretty->encode(fixture_payload());
}

1;
