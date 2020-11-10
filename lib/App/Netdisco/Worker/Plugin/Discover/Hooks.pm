package App::Netdisco::Worker::Plugin::Discover::Hooks;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::JobQueue 'jq_insert';
use MIME::Base64 'encode_base64';
use Encode 'encode';

register_worker({ phase => 'late' }, sub {
  my ($job, $workerconf) = @_;
  return unless vars->{'new_device'} and vars->{'hook_data'};

  foreach my $conf (@{ setting('hooks') }) {
    next unless scalar grep {$_ eq 'new_device'} @{ $conf->{'events'} };

    my $extra = { action_conf => $conf->{'with'},
                  event_data  => vars->{'hook_data'} };
    jq_insert({
      action => ('hook::'. $conf->{'type'}),
      extra  => encode_base64( encode('UTF-8', to_json( $extra )) ),
    });
  }

  return Status->info(sprintf 'Queued new_device Hook for %s.', $job->device);
});

true;
