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
    my $set = schema('netdisco')->resultset('Virtual::DuplexMismatch');
    return unless $set->count;

    content_type('text/html');
    template 'ajax/report/duplexmismatch.tt', {
      results => $set,
    }, { layout => undef };
};

true;
