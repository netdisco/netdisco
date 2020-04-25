package App::Netdisco::Web::Plugin::Device::Modules;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Util::Web (); # for sort_module
use App::Netdisco::Web::Plugin;

register_device_tab({ tag => 'modules', label => 'Modules' });

ajax '/ajax/content/device/modules' => require_login sub {
    my $q = param('q');

    my $device = schema('netdisco')->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);
    my @set = $device->modules->search({}, {order_by => { -asc => [qw/parent class pos index/] }});


    # sort modules (empty set would be a 'no records' msg)
    my $results = &App::Netdisco::Util::Web::sort_modules( \@set );
    return unless scalar %$results;
    use Data::Dumper; 
    #print STDERR "-----------\n"; print STDERR Dumper($results);

    print STDERR "-----------\n";
    print STDERR Dumper($results->{root}) ."\n";
    print STDERR "-----------\n";
    my $id = 1;
    print STDERR Dumper($results->{$id}{module}->name) ."\n";
    print STDERR Dumper($results->{$id}{module}->index) ."\n";
    print STDERR Dumper($results->{$id}{module}->parent) ."\n";
    print STDERR Dumper($results->{$id}->{children}) ."\n";
    print STDERR "-----------\n";

    content_type('text/html');
    template 'ajax/device/modules.tt', {
      nodes => $results,
    }, { layout => undef };
};

true;
