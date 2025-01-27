package App::Netdisco::Transport::Python;

use Dancer qw/:syntax :script/;

use base 'Dancer::Object::Singleton';
use aliased 'App::Netdisco::Worker::Status';
use App::Netdisco::Util::Python 'py_cmd';

use IPC::Run 'harness';
use MIME::Base64 'decode_base64';
use Path::Class;
use File::ShareDir 'dist_dir';
use JSON::PP ();
use YAML::XS ();
use Try::Tiny;

=head1 NAME

App::Netdisco::Transport::Python

=head1 DESCRIPTION

Not really a transport, but has similar behaviour to a Transport.

Returns an object which has a live Python subprocess expecting
instruction to run worklets.

 my $runsub = App::Netdisco::Transport::Python->py_worklet();

=cut

__PACKAGE__->attributes(qw/ runner stdin stdout /);

sub init {
  my ( $class, $instance ) = @_;

  my $cmd = [ py_cmd('run_worklet') ];
  my ($stdin, $stdout);

  my $harness = harness(
    ($ENV{ND2_PYTHON_HARNESS_DEBUG} ? (debug => 1) : ()),
    $cmd,
    '<',  \$stdin,
    '1>', \$stdout,
    '2>', sub { debug $_[0] },
  );

  $instance->runner( $harness );
  $instance->stdin( \$stdin );
  $instance->stdout( \$stdout );

  return $instance;
}

=head1 py_worklet( )

Returns an object instance with a live Python subprocess.

Will die if Python cannot be run.

=cut

sub py_worklet {
  my ($self, $job, $workerconf) = @_;
  my $action = $workerconf->{action};

  my $coder = JSON::PP->new->utf8(1)
                           ->allow_nonref(1)
                           ->allow_unknown(1)
                           ->allow_blessed(1)
                           ->allow_bignum(1);

  # this is only really used the first time (pump calls start)
  $ENV{'ND2_JOB_METADATA'}  = $coder->encode( { %$job, device => (($job->device || '') .'') } );
  $ENV{'ND2_CONFIGURATION'} = $coder->encode( config() );
  $ENV{'ND2_FSM_TEMPLATES'} = Path::Class::Dir->new( dist_dir('App-Netdisco') )
                                ->subdir('python')->subdir('tfsm')->stringify;

  my $inref  = $self->stdin;
  my $outref = $self->stdout;
  
  debug
    sprintf "\N{RIGHTWARDS ARROW WITH HOOK} \N{SNAKE} dispatching to \%s",
      $workerconf->{pyworklet};

  $$inref = $workerconf->{pyworklet} ."\n";
  $self->runner->pump until ($$outref and $$outref =~ /^\.\Z/m);

  debug
    sprintf "\N{LEFTWARDS ARROW WITH HOOK} \N{SNAKE} returned from \%s",
      $workerconf->{pyworklet};

  chomp(my $stdout = $$outref);
  $stdout =~ s/\n\.//s;
  $$outref = ''; # this is important for the next worklet to run

  my $retdata = try { YAML::XS::Load(decode_base64($stdout)) }; # might explode
  $retdata = {} if not ref $retdata or 'HASH' ne ref $retdata;

  # use DDP;
  # p $retdata;

  my $status = $retdata->{status} || '';
  my $log = $retdata->{log}
    || ($status eq 'done' ? (sprintf '%s exit OK', $action)
                          : (sprintf '%s exit with status "%s"', $action, $status));

  # TODO support merging more deeply
  var($_ => $retdata->{vars}->{$_}) for keys %{ $retdata->{vars} || {} };

  return Status->$status($log);
}

true;
