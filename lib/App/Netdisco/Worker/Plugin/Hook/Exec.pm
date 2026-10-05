package App::Netdisco::Worker::Plugin::Hook::Exec;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use MIME::Base64 'decode_base64';
use Command::Runner;
use Template;

# a string cmd goes through the shell: only ip and ndo may be substituted
sub render_shell_cmd {
  my ($orig_cmd, $event_data) = @_;
  my $tt = Template->new({ ENCODING => 'utf8', STRICT => 1 });
  my $shell_data = { map {( $_ => $event_data->{$_} )} qw/ndo ip/ };

  my $cmd = undef;
  return ($cmd, undef) if $tt->process(\$orig_cmd, $shell_data, \$cmd);
  return (undef, sprintf '%s; a string cmd may use only [%% ip %%] and [%% ndo %%], '
    .'write cmd as a list to pass other event fields', $tt->error);
}

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $extra = from_json( decode_base64( $job->extra || '' ) );

  my $event_data  = { ('ndo' => $ENV{NETDISCO_DO}), %{ $extra->{'event_data'} || {} } };
  my $action_conf = $extra->{'action_conf'};

  return Status->error('missing cmd parameter to exec Hook')
    if !defined $action_conf->{'cmd'};

  my $tt = Template->new({ ENCODING => 'utf8' });
  my ($orig_cmd, $cmd) = ($action_conf->{'cmd'}, undef);
  $action_conf->{'cmd_is_template'} ||= 1
    if !exists $action_conf->{'cmd_is_template'};
  if ($action_conf->{'cmd_is_template'}) {
      if (ref $orig_cmd) {
          foreach my $part (@$orig_cmd) {
              my $tmp_part = undef;
              $tt->process(\$part, $event_data, \$tmp_part);
              push @$cmd, $tmp_part;
          }
      }
      else {
          my $error = undef;
          ($cmd, $error) = render_shell_cmd($orig_cmd, $event_data);
          return Status->error("exec Hook: $error") if defined $error;
      }
  }
  $cmd ||= $orig_cmd;

  my $result = Command::Runner->new(
    command => $cmd,
    timeout => ($action_conf->{'timeout'} || 60),
    env => {
      %ENV,
      ND_EVENT => $action_conf->{'event'},
      ND_DEVICE_IP => $event_data->{'ip'},
    },
  )->run();

  $result->{cmd} = $cmd;
  $job->subaction(to_json($result));

  if ($action_conf->{'ignore_failure'} or not $result->{'result'}) {
    return Status->done(sprintf 'Exec Hook: exit status %s', $result->{'result'});
  }
  else {
    return Status->error(sprintf 'Exec Hook: exit status %s', $result->{'result'});
  }
});

true;
