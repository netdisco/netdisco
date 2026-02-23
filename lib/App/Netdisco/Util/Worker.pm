package App::Netdisco::Util::Worker;

use Dancer ':syntax';
use App::Netdisco::JobQueue 'jq_insert';

use Encode 'encode';
use MIME::Base64 'encode_base64';

use Storable 'dclone';
use Data::Visitor::Tiny;

use base 'Exporter';
our @EXPORT = ('queue_hook');

sub queue_hook {
  my ($hook, $conf) = @_;
  my $hook_data = dclone (vars->{'hook_data'} || {});
  my $extra = { action_conf => dclone ($conf->{'with'} || {}),
                event_data  => dclone ($hook_data) };

  # remove scalar references which to_json cannot handle
  visit( $extra->{'event_data'}, sub {
    my ($key, $valueref) = @_;
    $$valueref = '' if ref $$valueref eq 'SCALAR';
  });

  # Extract device IP from hook_data for backend routing
  my $device_ip = $hook_data->{'ip'};

  my $job_spec = {
    action => ('hook::'. lc($conf->{'type'})),
    extra  => encode_base64( encode('UTF-8', to_json( $extra )), '' ),
  };

  # Include device parameter if available for proper backend routing
  $job_spec->{device} = $device_ip if defined $device_ip;

  jq_insert($job_spec);

  return 1;
}

true;
