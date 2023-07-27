package App::Netdisco::Worker::Plugin::Discover::Properties::Tags;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::Util::Web 'sort_port';
use App::Netdisco::Util::Permission 'acl_matches';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;
  return unless $device->in_storage;

  return unless setting('tags')
    and ref {} eq ref setting('tags')
    and exists setting('tags')->{'device'}
    and ref {} eq ref setting('tags')->{'device'};

  my $tags = setting('tags')->{'device'};
  my @tags_to_set = ();

  foreach my $tag (sort keys %$tags) {
      # lhs is tag, rhs matches device
      next unless acl_matches($device, $tags->{$tag});
      push @tags_to_set, $tag;
  }

  return unless scalar @tags_to_set;
  $device->update({ tags => \@tags_to_set });
  debug sprintf ' [%s] properties - set %s tag%s',
    $device->ip, scalar @tags_to_set, (scalar @tags_to_set > 1);
});

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;
  return unless $device->in_storage;

  return unless setting('tags')
    and ref {} eq ref setting('tags')
    and exists setting('tags')->{'device_port'}
    and ref {} eq ref setting('tags')->{'device_port'};

  my $tags = setting('tags')->{'device_port'};
  my %tags_to_set = ();
  my $port_map = {};

  # hook data appears after the Properties workers which are in early phase
  map { push @{ $port_map->{ $_->{port} } }, $_ }
    @{ vars->{'hook_data'}->{'ports'} || [] },
    grep { defined $_->{port} } @{ vars->{'hook_data'}->{'device_ips'} || [] };

  foreach my $tag (sort keys %$tags) {
      # lhs is tag, rhs is acl map
      my $maps = (ref {} eq ref $tags->{$tag}) ? [ $tags->{$tag} ]
                                               : ( $tags->{$tag} || [] );

      foreach my $map (@$maps) {
          foreach my $key (sort keys %$map) {
              # lhs matches device, rhs matches port
              next unless $key and $map->{$key};
              next unless acl_matches($device, $key);

              foreach my $port (sort { sort_port($a, $b) } keys %$port_map) {
                  next unless acl_matches($port_map->{$port}, $map->{$key});

                  push @{ $tags_to_set{$port} }, $tag;
              }
          }
      }
  }

  foreach my $port (sort keys %tags_to_set) {
      schema('netdisco')->resultset('DevicePort')
        ->search({ip => $device->ip, port => $port}, {for => 'update'})
        ->update({ tags => ( $tags_to_set{$port} || [] ) });

      debug sprintf ' [%s] properties - set %s tag%s on port %s',
        $device->ip, scalar @{ $tags_to_set{$port} },
        (scalar @{ $tags_to_set{$port} } > 1), $port;
  }
});

true;
