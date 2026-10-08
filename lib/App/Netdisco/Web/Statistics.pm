package App::Netdisco::Web::Statistics;

use Dancer ':syntax';
use File::Spec::Functions qw/catfile catdir/;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

sub mib_bundle_version {
    my $home = setting('mibhome')
      || catdir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'netdisco-mibs');
    open my $fh, '<', catfile($home, 'VERSION') or return undef;
    my $version = <$fh>;
    close $fh;
    return undef unless defined $version;
    $version =~ s/^\s+|\s+$//g;
    return ($version =~ /\A[0-9]+(?:\.[0-9]+)+\z/ ? $version : undef);
}

get '/ajax/content/statistics' => require_login sub {

    my $stats = schema(vars->{'tenant'})->resultset('Statistics')
      ->search(undef, { order_by => { -desc => 'day' }, rows => 1 });

    $stats = ($stats->count ? $stats->first : undef);

    var( nav => 'statistics' );
    template 'ajax/statistics.tt',
        { stats => $stats, netdisco_version => $App::Netdisco::VERSION,
          mib_bundle_version => mib_bundle_version() },
        { layout => 'noop' };
};

true;
