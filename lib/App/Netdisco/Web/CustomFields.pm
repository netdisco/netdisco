package App::Netdisco::Web::CustomFields;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

set('_inline_actions' => []);

foreach my $config (@{ setting('custom_fields')->{'device'} || [] }) {

  if (! $config->{'name'}) {
      error 'custom_field missing name';
      next;
  }

  register_device_details({
    %{ $config },
    label => ($config->{'label'} || ucfirst $config->{'name'}),
  });

  push @{ setting('_inline_actions') },
       ('device_custom_field_' . $config->{'name'});

}

true;
