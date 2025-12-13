package App::Netdisco::Web::Plugin::Device::Neighbors;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use List::Util 'first';
use List::MoreUtils ();
use HTML::Entities 'encode_entities';
use App::Netdisco::Util::Port 'to_speed';
use App::Netdisco::Util::Permission qw/acl_matches acl_matches_only/;
use App::Netdisco::Web::Plugin;

register_device_tab({ tag => 'netmap', label => 'Neighbors' });

ajax '/ajax/content/device/netmap' => require_login sub {
    content_type('text/html');
    template 'ajax/device/netmap.tt', {}, { layout => undef };
};

ajax '/ajax/data/device/netmappositions' => require_login sub {
    my $q = param('q');
    my $qdev = schema(vars->{'tenant'})->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);

    my $p = param('positions') or send_error('Missing positions', 400);
    my $positions = from_json($p) or send_error('Bad positions', 400);
    send_error('Bad positions', 400) unless ref [] eq ref $positions;

    my $vlan = param('vlan');
    undef $vlan if (defined $vlan and $vlan !~ m/^\d+$/);

    my $mapshow = param('mapshow');
    return if !defined $mapshow or $mapshow !~ m/^(?:all|cloud|depth)$/;
    my $depth = param('depth') || 1;
    return if $depth !~ m/^\d+$/;

    # list of groups selected by user and passed in param
    my $hgroup = (ref [] eq ref param('hgroup') ? param('hgroup') : [param('hgroup')]);
    # list of groups validated as real host groups and named host groups
    my @hgrplist = List::MoreUtils::uniq
                   grep { exists setting('host_group_displaynames')->{$_} }
                   grep { exists setting('host_groups')->{$_} }
                   grep { defined } @{ $hgroup };

    # list of locations selected by user and passed in param
    my $lgroup = (ref [] eq ref param('lgroup') ? param('lgroup') : [param('lgroup')]);
    my @lgrplist = List::MoreUtils::uniq grep { defined } @{ $lgroup };

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

    my $posrow = schema(vars->{'tenant'})->resultset('NetmapPositions')->find({
      device => ($mapshow ne 'all' ? $qdev->ip : undef),
      depth  => ($mapshow eq 'depth' ? $depth : 0),
      host_groups => \[ '= ?', [host_groups => [sort @hgrplist]] ],
      locations   => \[ '= ?', [locations   => [sort @lgrplist]] ],
      vlan => ($vlan || 0),
    });

    if ($posrow) {
      $posrow->update({ positions => to_json(\%clean) });
    }
    else {
      schema(vars->{'tenant'})->resultset('NetmapPositions')->create({
        device => ($mapshow ne 'all' ? $qdev->ip : undef),
        depth  => ($mapshow eq 'depth' ? $depth : 0),
        host_groups => [sort @hgrplist],
        locations   => [sort @lgrplist],
        vlan => ($vlan || 0),
        positions => to_json(\%clean),
      });
    }
};

sub make_node_infostring {
  my $node = shift or return '';
  my $fmt = ('<b>%s</b> is %s <b>%s %s</b><br>running <b>%s %s</b><br>Serial: <b>%s</b><br>'
    .'Uptime: <b>%s</b><br>Location: <b>%s</b><br>Contact: <b>%s</b>');
  
  my @field_values = ();
  if (ref [] eq ref setting('netmap_custom_fields')->{device}) {
      foreach my $field (@{ setting('netmap_custom_fields')->{device} }) {
          foreach my $config (@{ setting('custom_fields')->{device} }) {
              next unless $config->{'name'} and $config->{'name'} eq $field;

              next if $config->{json_list};
              next if acl_matches($node->ip, ($config->{no} || []));
              next unless acl_matches_only($node->ip, ($config->{only} || []));
              $fmt .= sprintf '<br>%s: <b>%%s</b>', ($config->{label} || ucfirst($config->{name}));
              push @field_values, ('cf_'. $config->{name});
          }
      }
  }

  return sprintf $fmt, $node->ip,
    ((($node->vendor || '') =~ m/^[aeiou]/i) ? 'an' : 'a'),
    encode_entities(ucfirst($node->vendor || '')),
    (map {defined $_ ? encode_entities($_) : ''}
        map {$node->$_}
            (qw/model os os_ver serial uptime_age location contact/)),
    map {encode_entities($node->get_column($_) || '')} @field_values;
}

sub make_link_infostring {
  my $link = shift or return '';

  my $domains = setting('domain_suffix');
  (my $left_name = lc($link->{left_dns} || $link->{left_name} || $link->{left_ip})) =~ s/$domains//;
  (my $right_name = lc($link->{right_dns} || $link->{right_name} || $link->{right_ip})) =~ s/$domains//;

  my @zipped = List::MoreUtils::zip6
    @{$link->{left_port}}, @{$link->{left_descr}},
    @{$link->{right_port}}, @{$link->{right_descr}};

  return join '<br><br>', map { sprintf '<b>%s:%s</b> (%s)<br><b>%s:%s</b> (%s)',
    encode_entities($left_name), encode_entities($_->[0]), encode_entities(($_->[1] || 'no description')),
    encode_entities($right_name), encode_entities($_->[2]), encode_entities(($_->[3] || 'no description')) } @zipped;
}

get '/ajax/data/device/netmap' => require_login sub {
    my $q = param('q');
    my $qdev = schema(vars->{'tenant'})->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);

    my $vlan = param('vlan');
    undef $vlan if (defined $vlan and $vlan !~ m/^\d+$/);

    my $colorby = (param('colorby') || 'speed');
    my $mapshow = (param('mapshow') || 'depth');
    my $depth   = (param('depth')   || 1);
    $mapshow = 'depth' if $mapshow !~ m/^(?:all|cloud|depth)$/;
    $mapshow = 'all' unless $qdev->in_storage;

    # list of groups selected by user and passed in param
    my $hgroup = (ref [] eq ref param('hgroup') ? param('hgroup') : [param('hgroup')]);
    # list of groups validated as real host groups and named host groups
    my @hgrplist = List::MoreUtils::uniq
                   grep { exists setting('host_group_displaynames')->{$_} }
                   grep { exists setting('host_groups')->{$_} }
                   grep { defined } @{ $hgroup };

    # list of locations selected by user and passed in param
    my $lgroup = (ref [] eq ref param('lgroup') ? param('lgroup') : [param('lgroup')]);
    my @lgrplist = List::MoreUtils::uniq grep { defined } @{ $lgroup };

    my %ok_dev = ();
    my %logvals = ();
    my %metadata = ();
    my %data = ( nodes => [], links => [] );
    my $domains = setting('domain_suffix');

    # LINKS

    my %seen_link = ();
    my $links = schema(vars->{'tenant'})->resultset('Virtual::DeviceLinks')->search({
      (($mapshow eq 'depth' and $depth == 1) ? ( -or => [
          { left_ip  => $qdev->ip },
          { right_ip => $qdev->ip },
      ]) : ())
    }, { result_class => 'DBIx::Class::ResultClass::HashRefInflator' });

    while (my $link = $links->next) {
      # query is ordered by aggregate speed desc so we see highest speed
      # first, which is hopefully the "best" if links are not symmetric
      next if exists $seen_link{$link->{left_ip} ."\0". $link->{right_ip}}
           or exists $seen_link{$link->{right_ip} ."\0". $link->{left_ip}};

      push @{$data{'links'}}, {
        FROMID => $link->{left_ip},
        TOID   => $link->{right_ip},
        INFOSTRING => make_link_infostring($link),
        SPEED  => to_speed($link->{aggspeed}),
      };

      ++$ok_dev{$link->{left_ip}};
      ++$ok_dev{$link->{right_ip}};
      ++$seen_link{$link->{left_ip} ."\0". $link->{right_ip}};
    }

    # filter by lldp cloud or depth
    # this is O(N^2) or worse

    my %cloud = ($qdev->ip => 1);
    my $seen_cloud = scalar keys %cloud;
    my $passes = ($mapshow eq 'cloud' ? 999 : $depth);

    if ($mapshow eq 'cloud' or ($mapshow eq 'depth' and $depth > 1)) {
        while ($seen_cloud > 0 and $passes > 0) {
            --$passes;
            $seen_cloud = 0;

            foreach my $cip (keys %cloud) {
                foreach my $okip (keys %ok_dev) {
                    next if exists $cloud{$okip};

                    if (exists $seen_link{$cip ."\0". $okip}
                        or exists $seen_link{$okip ."\0". $cip}) {

                        ++$cloud{$okip};
                        ++$seen_cloud;
                    }
                }
            }
        }
    }
    elsif ($mapshow eq 'depth' and $depth == 1) {
        %cloud = %ok_dev;
    }

    # DEVICES (NODES)

    my $posrow = schema(vars->{'tenant'})->resultset('NetmapPositions')->find({
      device => ($mapshow ne 'all' ? $qdev->ip : undef),
      depth  => ($mapshow eq 'depth' ? $depth : 0),
      host_groups => \[ '= ?', [host_groups => [sort @hgrplist]] ],
      locations   => \[ '= ?', [locations   => [sort @lgrplist]] ],
      vlan => ($vlan || 0),
    });
    my $pos_for = from_json( $posrow ? $posrow->positions : '{}' );

    my $devices = schema(vars->{'tenant'})->resultset('Device')->search({}, {
      '+select' => [\'floor(log(throughput.total))'], '+as' => ['log'],
      join => 'throughput', distinct => 1,
    })->with_times;
    
    $devices = $devices->with_custom_fields
      if scalar @{ setting('netmap_custom_fields')->{'device'} };

    # filter by vlan for all or neighbors only
    if ($vlan) {
      $devices = $devices->search(
        { 'port_vlans_filter.vlan' => $vlan },
        { join => 'port_vlans_filter' }
      );
    }

    DEVICE: while (my $device = $devices->next) {
      # if in neighbors mode then use %ok_dev to filter
      next DEVICE if ($device->ip ne $qdev->ip)
        and ($mapshow ne 'all')
        and (not $cloud{$device->ip}); # showing only neighbors but no link

      # if location picked then filter
      next DEVICE if ((scalar @lgrplist) and ((!defined $device->location)
        or (0 == scalar grep {$_ eq $device->location} @lgrplist)));

      # if host groups picked then use ACLs to filter
      my $first_hgrp =
        first { acl_matches($device, setting('host_groups')->{$_}) } @hgrplist;
      next DEVICE if ((scalar @hgrplist) and (not $first_hgrp));

      # now reset first_hgroup to be the group matching the device, if any
      $first_hgrp = first { acl_matches($device, setting('host_groups')->{$_}) }
                          keys %{ setting('host_group_displaynames') || {} };

      ++$logvals{ $device->get_column('log') || 1 };
      (my $name = lc($device->dns || $device->name || $device->ip)) =~ s/$domains//;

      my %color_lkp = (
        speed => (($device->get_column('log') || 1) * 1000),
        hgroup => ($first_hgrp ?
          setting('host_group_displaynames')->{$first_hgrp} : 'Other'),
        lgroup => ($device->location || 'Other'),
      );

      my $node = {
        ID => $device->ip,
        SIZEVALUE => (param('dynamicsize') ? $color_lkp{speed} : 3000),
        ((exists $color_lkp{$colorby}) ? (COLORVALUE => $color_lkp{$colorby}) : ()),
        (($device->ip eq $qdev->ip) ? (COLORVALUE => 'ROOTNODE') : ()),
        LABEL => (param('showips') ? ($device->ip .' '. $name) : $name),
        ORIG_LABEL => $name,
        INFOSTRING => make_node_infostring($device),
        LINK => uri_for('/device', {
          tab => 'netmap',
          q => $device->ip,
          firstsearch => 'on',
        })->path_query,
      };

      if (exists $pos_for->{$device->ip}) {
        $node->{'fixed'} = 1;
        $node->{'x'} = $pos_for->{$device->ip}->{'x'};
        $node->{'y'} = $pos_for->{$device->ip}->{'y'};
      }
      else {
        ++$metadata{'newnodes'};
      }

      push @{$data{'nodes'}}, $node;
      $metadata{'centernode'} = $device->ip
        if $qdev and $qdev->in_storage and $device->ip eq $qdev->ip;
    }

    # to help get a sensible range of node sizes
    $metadata{'numsizes'} = scalar keys %logvals;

    content_type('application/json');
    to_json({ data => \%data, %metadata });
};

true;
