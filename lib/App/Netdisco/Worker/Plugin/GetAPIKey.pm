package App::Netdisco::Worker::Plugin::GetAPIKey;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

register_worker({ phase => 'check' }, sub {
  return Status->error('Missing user (-e).')
    unless shift->extra;
  return Status->done('GetAPIKey is able to run');
});

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $username = $job->extra;

  my $user = schema('netdisco')->resultset('User')
    ->find({ username => $username });

  return Status->error("No such user")
    unless $user and $user->in_storage;

  # from the internals of Dancer::Plugin::Auth::Extensible
  my $provider = Dancer::Plugin::Auth::Extensible::auth_provider('users');

  # if there's a current valid token then reissue it and reset timer
  $user->update({
      token_from => time,
      ($provider->validate_api_token($user->token)
        ? () : (token => \'md5(random()::text)')),
    })->discard_changes();

  return Status->done(
    sprintf 'Set token for user %s: %s', $username, $user->token);
});

true;
