package App::Netdisco::Web::Plugin::Report::HalfDuplex;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report({
  category => 'Port',
  tag => 'halfduplex',
  label => 'Ports in Half Duplex Mode',
  provides_csv => 1,
});

get '/ajax/content/report/halfduplex' => require_login sub {
    my $format = param('format');
    my $set = schema('netdisco')->resultset('DevicePort')->search(
      { up => 'up', duplex => { '-ilike' => 'half' } },
      { order_by => [qw/device.dns port/], prefetch => 'device' },
    );
    return unless $set->count;

    if (request->is_ajax) {
        template 'ajax/report/halfduplex.tt', { results => $set, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/halfduplex_csv.tt', { results => $set, },
            { layout => undef };
    }
};

true;
