package App::Netdisco::Web::CustomFields;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

use App::Netdisco::DB::ResultSet::Device;
use App::Netdisco::DB::ResultSet::DevicePort;

use App::Netdisco::Web::Plugin;

my @inline_device_actions = ();
my @inline_device_port_actions = ();

foreach my $config (@{ setting('custom_fields')->{'device'} || [] }) {

  if (! $config->{'name'}) {
      error 'custom_field missing name';
      next;
  }

  register_device_details({
    %{ $config },
    field => ('cf_' . $config->{'name'}),
    label => ($config->{'label'} || ucfirst $config->{'name'}),
  });

  push @inline_device_actions, $config->{'name'};

}

foreach my $config (@{ setting('custom_fields')->{'device_port'} || [] }) {

  if (! $config->{'name'}) {
      error 'custom_field missing name';
      next;
  }

  register_device_port_column({
    position => 'right', # or "mid" or "right"
    default  => undef,   # or undef
    %{ $config },
    field => ('cf_' . $config->{'name'}),
    label => ($config->{'label'} || ucfirst $config->{'name'}),
  });

  push @inline_device_port_actions, $config->{'name'};

}

{
  package App::Netdisco::DB::ResultSet::Device;

  sub with_custom_fields {
    my ($rs, $cond, $attrs) = @_;

    return $rs
      ->search_rs($cond, $attrs)
      ->search({},
        { '+columns' => {
            map {( ('cf_'. $_) => \[ 'me.custom_fields ->> ?' => $_ ] )}
                @inline_device_actions
        }});
  }
}

{
  package App::Netdisco::DB::ResultSet::DevicePort;

  sub with_custom_fields {
    my ($rs, $cond, $attrs) = @_;

    return $rs
      ->search_rs($cond, $attrs)
      ->search({},
        { '+columns' => {
            map {( ('cf_'. $_) => \[ 'me.custom_fields ->> ?' => $_ ] )}
                @inline_device_port_actions
        }});
  }
}

set('_inline_actions' => [
  map {'cf_' . $_} (@inline_device_actions, @inline_device_port_actions)
]);

true;
