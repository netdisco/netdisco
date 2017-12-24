package App::Netdisco::Web::Plugin::Device::Neighbors;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use List::Util 'first';
use List::MoreUtils ();
use App::Netdisco::Util::Permission 'check_acl_only';
use App::Netdisco::Web::Plugin;

register_device_tab({ tag => 'netmap', label => 'Neighbors' });

ajax '/ajax/content/device/netmap' => require_login sub {
    content_type('text/html');
    template 'ajax/device/netmap.tt', {}, { layout => undef };
};

ajax '/ajax/data/device/netmappositions' => require_login sub {
    my $p = param('positions') or send_error('Missing positions', 400);
    my $positions = from_json($p) or send_error('Bad positions', 400);
    send_error('Bad positions', 400) unless ref [] eq ref $positions;

    my $vlan = param('vlan');
    undef $vlan if (defined $vlan and $vlan !~ m/^\d+$/);

    my $mapshow = param('mapshow');
    return if !defined $mapshow or $mapshow !~ m/^(?:all|only)$/;

    # list of groups selected by user and passed in param
    my $devgrp = (ref [] eq ref param('devgrp') ? param('devgrp') : [param('devgrp')]);
    # list of groups validated as real host groups and named host groups
    my @hgrplist = List::MoreUtils::uniq
                   grep { exists setting('host_group_displaynames')->{$_} }
                   grep { exists setting('host_groups')->{$_} }
                   grep { defined } @{ $devgrp };
    return if $mapshow eq 'only' and 0 == scalar @hgrplist;
    push(@hgrplist, '__ANY__') if 0 == scalar @hgrplist;

    my %clean = ();
    POSITION: foreach my $pos (@$positions) {
      next unless ref {} eq ref $pos;
      foreach my $k (qw/ID x y/) {
        next POSITION unless exists $pos->{$k};
        next POSITION unless $pos->{$k} =~ m/^[[:word:]\.-]+$/;
      }
      $clean{$pos->{ID}} = { x => $pos->{x}, y => $pos->{y} };
    }
    return unless scalar keys %clean;

    my $posrow = schema('netdisco')->resultset('NetmapPositions')->find({
      device_groups => \[ '= ?', [device_groups => [sort @hgrplist]] ],
      vlan => ($vlan || 0)});
    if ($posrow) {
      $posrow->update({ positions => to_json(\%clean) });
    }
    else {
      schema('netdisco')->resultset('NetmapPositions')->create({
        device_groups => [sort @hgrplist],
        vlan => ($vlan || 0),
        positions => to_json(\%clean),
      });
    }
};

ajax '/ajax/data/device/netmap' => require_login sub {
    my $q = param('q');
    my $qdev = schema('netdisco')->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);

    my $vlan = param('vlan');
    undef $vlan if (defined $vlan and $vlan !~ m/^\d+$/);

    my $mapshow = (param('mapshow') || 'neighbors');
    $mapshow = 'neighbors' if $mapshow !~ m/^(?:all|neighbors|only)$/;
    $mapshow = 'all' unless $qdev->in_storage;

    # list of groups selected by user and passed in param
    my $devgrp = (ref [] eq ref param('devgrp') ? param('devgrp') : [param('devgrp')]);
    # list of groups validated as real host groups and named host groups
    my @hgrplist = List::MoreUtils::uniq
                   grep { exists setting('host_group_displaynames')->{$_} }
                   grep { exists setting('host_groups')->{$_} }
                   grep { defined } @{ $devgrp };

    my %id_for = ();
    my %ok_dev = ();
    my %v3data = ( nodes => {}, links => [] );
    my %v4data = ( nodes => [], links => [] );
    my $domain = quotemeta( setting('domain_suffix') || '' );

    # LINKS

    my $rs = schema('netdisco')->resultset('Virtual::DeviceLinks')->search({
      ($mapshow eq 'neighbors' ? ( -or => [
          { left_ip  => $qdev->ip },
          { right_ip => $qdev->ip },
      ]) : ())
    }, {
      columns => [qw/left_ip right_ip/],
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    });

    if ($vlan) {
        $rs = $rs->search({
          -or => [
            { 'left_vlans.vlan' => $vlan },
            { 'right_vlans.vlan' => $vlan },
          ],
        }, {
          join => [qw/left_vlans right_vlans/],
        });
    }

    my @links = $rs->all; # because we have to run this twice
    foreach my $l (@links) {
      push @{$v3data{'links'}}, {
        FROMID => $l->{left_ip},
        TOID   => $l->{right_ip},
      };

      ++$ok_dev{$l->{left_ip}};
      ++$ok_dev{$l->{right_ip}};
    }

    # DEVICES (NODES)

    my $posrow = schema('netdisco')->resultset('NetmapPositions')->find({
      device_groups => \[ '= ?',
        [device_groups => [$mapshow eq 'all' ? '__ANY__' : (sort @hgrplist)]] ],
      vlan => ($vlan || 0)});
    my $pos_for = from_json( $posrow ? $posrow->positions : '{}' );

    my $devices = schema('netdisco')->resultset('Device')->search({}, {
      columns => ['ip', 'dns', 'name'],
      '+select' => [\'row_number() over()', \'floor(log(throughput.total))'],
      '+as' => ['row_number', 'log'],
      join => 'throughput',
    });

    DEVICE: while (my $device = $devices->next) {
      # if in neighbors or vlan mode then use %ok_dev to filter
      next DEVICE if (($mapshow eq 'neighbors') or $vlan)
        and (not $ok_dev{$device->ip});

      # if in only mode then use ACLs to filter
      my $first_hgrp =
        first { check_acl_only($device, setting('host_groups')->{$_}) } @hgrplist;
      next DEVICE if $mapshow eq 'only' and not $first_hgrp;

      $id_for{$device->ip} = $device->get_column('row_number');
      (my $name = lc($device->dns || $device->name || $device->ip)) =~ s/$domain$//;

      $v3data{nodes}->{ ($device->get_column('row_number') - 1) } = {
        ID => $device->ip,
        SIZEVALUE => (param('dynamicsize') ?
          (($device->get_column('log') || 1) * 1000) : 3000),
        (param('colorgroups') ?
          (COLORVALUE => ($first_hgrp ? setting('host_group_displaynames')->{$first_hgrp} : 'Other')) : ()),
        LABEL => $name,
      };

      if (exists $pos_for->{$device->ip}) {
        my $node = $v3data{nodes}->{ ($device->get_column('row_number') - 1) };
        $node->{'fixed'} = 1;
        $node->{'x'} = $pos_for->{$device->ip}->{'x'};
        $node->{'y'} = $pos_for->{$device->ip}->{'y'};
      }
      else {
        ++$v3data{'newnodes'};
      }

      $v3data{'centernode'} = $device->ip
        if $qdev and $qdev->in_storage and $device->ip eq $qdev->ip;

      push @{$v4data{'nodes'}}, { index => ($device->get_column('row_number') - 1) };
    }

    # go back and do v4 links now we have row IDs
    foreach my $l (@links) {
      next unless $id_for{$l->{left_ip}} and $id_for{$l->{right_ip}};
      push @{$v4data{'links'}}, {
        source => ($id_for{$l->{left_ip}} - 1),
        target => ($id_for{$l->{right_ip}} - 1),
      };
    }

    content_type('application/json');
    to_json({ v3 => \%v3data, v4 => \%v4data});
};

true;
