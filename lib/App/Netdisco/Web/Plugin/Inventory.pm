package App::Netdisco::Web::Plugin::Inventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_navbar_item({
  tag   => 'inventory',
  path  => '/inventory',
  label => 'Inventory',
});

get '/inventory' => require_login sub {
    my $platforms = schema(vars->{'tenant'})->resultset('Device')->get_platforms();
    my $releases = schema(vars->{'tenant'})->resultset('Device')->get_releases();

    my %release_version_map = (
      map  { (join '', map {sprintf '%05s', $_} split m/(\D)/, ($_->{os_ver} || '')) => $_ }
      $releases->hri->all
    );

    my %release_map = ();
    map  { push @{ $release_map{ $release_version_map{$_}->{os} } }, $release_version_map{$_} }
    grep { $release_version_map{$_}->{os} }
    grep { $_ }
    sort {(lc($release_version_map{$a}->{os} || '') cmp lc($release_version_map{$b}->{os} || '')) || ($a cmp $b)}
         keys %release_version_map;

    my %release_totals =
      map  { $_ => {rows => scalar @{ $release_map{$_} }, count => 0} }
      grep { $_ }
           keys %release_map;

    foreach my $r (keys %release_totals) {
      map { $release_totals{$r}->{count} += $_->{count} }
          @{ $release_map{ $r } };
    }

    my %platform_map = ();
    map  { push @{ $platform_map{$_->{vendor}} }, $_ }
    grep { $_->{vendor} }
    grep { $_ }
    sort {(lc($a->{vendor} || '') cmp lc($b->{vendor} || '')) || (lc($a->{model} || '') cmp lc($b->{model} || ''))}
         $platforms->hri->all;

    my %platform_totals =
      map  { $_ => {rows => scalar @{ $platform_map{$_} }, count => 0} }
      grep { $_ }
           keys %platform_map;

    foreach my $r (keys %platform_totals) {
      map { $platform_totals{$r}->{count} += $_->{count} }
          @{ $platform_map{ $r } };
    }

    var(nav => 'inventory');
    template 'inventory', {
      platforms => [ sort keys %platform_totals ],
      releases  => [ sort keys %release_totals ],
      platform_map => \%platform_map,
      release_map  => \%release_map,
      platform_totals => \%platform_totals,
      release_totals  => \%release_totals,
    }, { layout => 'main' };
};

true;
