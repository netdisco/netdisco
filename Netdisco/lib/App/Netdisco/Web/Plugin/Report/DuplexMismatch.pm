package App::Netdisco::Web::Plugin::Report::DuplexMismatch;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use App::Netdisco::Web::Plugin;

register_report({
  category => 'Port',
  tag => 'duplexmismatch',
  label => 'Duplex Mismatches Between Devices',
});

ajax '/ajax/content/report/duplexmismatch' => sub {
#    my $q = param('q');
#    my $device = schema('netdisco')->resultset('Device')
#      ->with_times()->search_for_device($q) or return;

    content_type('text/html');
    template 'ajax/report/duplexmismatch.tt', {
#      d => $device,
    }, { layout => undef };
};

true;
