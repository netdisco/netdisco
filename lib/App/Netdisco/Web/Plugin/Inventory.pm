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
    my $platforms = schema('netdisco')->resultset('Device')->get_platforms();
    my $releases = schema('netdisco')->resultset('Device')->get_releases();

    my %release_map = (
      map  { (join '', map {sprintf '%05s', $_} split m/(\D)/, ($_->{os_ver} || '')) => $_ }
      $releases->hri->all
    );
    my @release_list =
      map  { $release_map{$_} }
      sort {(($release_map{$a}->{os} || '') cmp ($release_map{$b}->{os} || '')) || ($a cmp $b)}
           keys %release_map;

    var(nav => 'inventory');
    template 'inventory', {
      platforms => [ $platforms->hri->all ],
      releases  => [ @release_list ],
    }, { layout => 'main' };
};

true;
