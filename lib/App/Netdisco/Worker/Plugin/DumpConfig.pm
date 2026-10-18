package App::Netdisco::Worker::Plugin::DumpConfig;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Data::Printer;
use Scalar::Util 'blessed';
use Try::Tiny;
use App::Netdisco::Util::Configuration 'effective_setting';

# settings the ACL Manager adds to, printed as Netdisco will use them
my @effective = qw/portctl_by_role host_groups/;

# domain_suffix is a compiled Regexp and url_base a URI::Based, and JSON
# encodes neither. Data::Printer renders them, so only the quiet path needs it.
sub _json_safe {
  my $node = shift;
  return $node if !ref $node or ref $node eq 'SCALAR';
  return "$node" if blessed $node;
  return [ map { _json_safe($_) } @$node ] if ref $node eq 'ARRAY';
  return { map {($_ => _json_safe($node->{$_}))} keys %$node }
    if ref $node eq 'HASH';
  return undef;
}

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $extra = $job->extra;
  my $print_this_instead = $job->port;

  if (! $ENV{ND2_DO_QUIET}) {
      debug sprintf 'port: "%s"', ($print_this_instead || '');
      debug sprintf 'subaction: "%s"', ($extra || '');
  }

  my $key = ($print_this_instead || $extra);
  my $CONFIG = config();

  # Job promotes an undefined subaction to empty string, so an unkeyed
  # dumpconfig arrives here as q{} and must still dump everything.
  my $wanted = (((defined $key) and (ref $key eq q{}) and (length $key))
    ? $key : undef);

  # dumpconfig shows the configuration Netdisco will use, ACL Manager roles
  # included. it is also how a broken install is diagnosed, so without the
  # database it shows the YAML, and says so once.
  my %effective = ();
  if (not defined $wanted or scalar grep { $_ eq $wanted } @effective) {
      try {
          $effective{$_} = effective_setting($_) for @effective;
      }
      catch {
          warning "dumpconfig: database ACLs not included: $_";
          %effective = ();
      };
  }

  my $dump = (defined $wanted
    ? (exists $effective{$wanted} ? $effective{$wanted} : $CONFIG->{$wanted})
    : { %$CONFIG, %effective });
  p $dump unless $ENV{ND2_DO_QUIET};

  return Status->done($ENV{ND2_DO_QUIET}
    ? to_json(_json_safe($dump)) : 'Dumped config');
});

true;
