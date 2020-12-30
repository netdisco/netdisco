package App::Netdisco::Worker::Plugin::Hook::HTTP;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use MIME::Base64 'decode_base64';
use HTTP::Tiny;
use Template;

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $extra = from_json( decode_base64( $job->extra || '' ) );
  $job->subaction('');

  my $event_data  = $extra->{'event_data'};
  my $action_conf = $extra->{'action_conf'};
  $action_conf->{'body'} ||= to_json($event_data);

  return Status->error('missing url parameter to http Hook')
    if !defined $action_conf->{'url'};

  my $tt = Template->new({ ENCODING => 'utf8' });
  my $http = HTTP::Tiny
    ->new( timeout => (($action_conf->{'timeout'} || 5000) / 1000) );

  $action_conf->{'custom_headers'} ||= {};
  $action_conf->{'custom_headers'}->{'Content-Type'}
    ||= 'application/json; charset=UTF-8';
  $action_conf->{'custom_headers'}->{'Authorization'}
    = ('Bearer '. $action_conf->{'bearer_token'})
      if $action_conf->{'bearer_token'};

  my ($orig_url, $url) = ($action_conf->{'url'}, undef);
  $action_conf->{'url_is_template'} ||= 1
    if !exists $action_conf->{'url_is_template'};
  $tt->process(\$orig_url, $event_data, \$url)
    if $action_conf->{'url_is_template'};
  $url ||= $orig_url;

  my ($orig_body, $body) = ($action_conf->{'body'} , undef);
  $action_conf->{'body_is_template'} ||= 1
    if !exists $action_conf->{'body_is_template'};
  $tt->process(\$orig_body, $event_data, \$body)
    if $action_conf->{'body_is_template'};
  $body ||= $orig_body;

  my $response = $http->request(
    ($action_conf->{'method'} || 'POST'), $url,
    { headers => $action_conf->{'custom_headers'},
      content => $body },
  );

  if ($action_conf->{'ignore_failure'} or $response->{'success'}) {
    return Status->done(sprintf 'HTTP Hook: %s %s',
      $response->{'status'}, $response->{'reason'});
  }
  else {
    return Status->error(sprintf 'HTTP Hook: %s %s',
      $response->{'status'}, $response->{'reason'});
  }
});

true;
