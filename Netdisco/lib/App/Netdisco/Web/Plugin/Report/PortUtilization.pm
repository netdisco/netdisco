package App::Netdisco::Web::Plugin::Report::PortUtilization;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report({
  category => 'Device',
  tag => 'portutilization',
  label => 'Port Utilization',
});

ajax '/ajax/content/report/portutilization' => require_login sub {
    return unless schema('netdisco')->resultset('Device')->count;
    my $set = schema('netdisco')->resultset('Virtual::PortUtilization');

    content_type('text/html');
    template 'ajax/report/portutilization.tt', {
      results => $set,
    }, { layout => undef };
};

true;
