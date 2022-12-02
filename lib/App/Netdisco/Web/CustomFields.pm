package App::Netdisco::Web::CustomFields;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

my @inline_actions = ();

foreach my $config (@{ setting('custom_fields')->{'device'} || [] }) {

  if (! $config->{'name'}) {
      error 'custom_field missing name';
      next;
  }

  register_device_details({
    %{ $config },
    label => ($config->{'label'} || ucfirst $config->{'name'}),
  });

  push @inline_actions, $config->{'name'};

}

schema(vars->{'tenant'})->resultset('Device')->result_source
  ->resultset_attributes({ '+columns' => {
    map {( $_ => \[ 'me.custom_fields ->> ?' => $_ ] )}
        @inline_actions
  } });

set('_inline_actions' => [ map {'device_custom_field_' . $_}
                               @inline_actions ]);

true;
