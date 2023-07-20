package App::Netdisco::Web::CustomFields;

use Dancer ':syntax';

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::CustomFields;

foreach my $config (@{ setting('custom_fields')->{'device'} || [] }) {
  next unless $config->{'name'};

  register_device_details({
    %{ $config },
    field => ('cf_' . $config->{'name'}),
    label => ($config->{'label'} || ucfirst $config->{'name'}),
  }) unless $config->{'hidden'};
}

foreach my $config (@{ setting('custom_fields')->{'device_port'} || [] }) {
  next unless $config->{'name'};

  register_device_port_column({
    position => 'right', # or "mid" or "right"
    default  => undef,   # or "checked"
    %{ $config },
    field => ('cf_' . $config->{'name'}),
    label => ($config->{'label'} || ucfirst $config->{'name'}),
  }) unless $config->{'hidden'};
}

true;
