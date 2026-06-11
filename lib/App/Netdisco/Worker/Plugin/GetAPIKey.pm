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
  my $username  = $job->extra;
  my $flag      = $job->port || '';

  my $user = schema('netdisco')->resultset('User')
    ->find_or_create({ username => $username });

  if ($flag eq 'revoke') {
    $user->update({ token => undef, token_from => undef, token_no_expire => \"false" });
    return Status->done(sprintf 'Revoked API token for user %s', $username);
  }

  # from the internals of Dancer::Plugin::Auth::Extensible
  my $provider = Dancer::Plugin::Auth::Extensible::auth_provider('users');

  my %updates = (
    token_from     => time,
    token_no_expire => ($flag eq 'permanent' ? \"true" : \"false"),
    ($provider->validate_api_token($user->token)
      ? () : (token => \'md5(random()::text)')),
  );

  $user->update(\%updates)->discard_changes();

  return Status->done(
    sprintf 'Set %s token for user %s: %s',
      ($flag eq 'permanent' ? 'permanent' : 'session'),
      $username, $user->token);
});

true;
