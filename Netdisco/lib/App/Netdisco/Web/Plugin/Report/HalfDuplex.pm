package App::Netdisco::Web::Plugin::Report::HalfDuplex;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report({
  category => 'Port',
  tag => 'halfduplex',
  label => 'Ports in Half Duplex Mode',
});

ajax '/ajax/content/report/halfduplex' => require_login sub {
    my $set = schema('netdisco')->resultset('DevicePort')->search(
      { up => 'up', duplex => { '-ilike' => 'half' } },
      { order_by => [qw/device.dns port/], prefetch => 'device' },
    );
    return unless $set->count;

    content_type('text/html');
    template 'ajax/report/halfduplex.tt', {
      results => $set,
    }, { layout => undef };
};

true;
