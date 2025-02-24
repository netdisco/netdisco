package App::Netdisco::Worker::Plugin::Snapshot;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;
use MIME::Base64 'encode_base64';

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  return Status->error('Missing device (-d).')
    unless defined $device;

  return Status->error(sprintf 'Unknown device: %s', ($device || ''))
    unless $device and $device->in_storage;

  #return Status->defer("bulkwalk skipped: please run a loadmibs job first")
  #  unless schema('netdisco')->resultset('SNMPObject')->count();

  return Status->done('Bulkwalk is able to run');
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $port, $extra) = map {$job->$_} qw/device port extra/;

  set(net_snmp_options => {
    %{ setting('net_snmp_options') },
    'UseLongNames' => 1,	   # Return full OID tags
    'UseSprintValue' => 0,
    'UseEnums'	=> 0,	   # Don't use enumerated vals
    'UseNumeric' => 1,	   # Return dotted decimal OID
  });

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device);
  my $from = SNMP::Varbind->new([ $extra || '.1' ]);
  my $vars = [];
  my $errornum = 0;
  my %seen = ();
  my $sess = $snmp->session();

  ($vars) = $sess->bulkwalk( 0, $snmp->{BulkRepeaters}, $from );
  if ( $sess->{ErrorNum} ) {
      return Status->error(
          sprintf 'snmp fatal error - %s', $sess->{ErrorStr});
  }

  while (not $errornum) {
      my $var = shift @$vars or last;
      my $idx = $var->[0];
      $idx .= '.'. $var->[1] if $var->[1];
      my $val = $var->[2];
      my $type = $var->[3];

      # Check if last element, V2 devices may report ENDOFMIBVIEW even if
      # instance or object doesn't exist.
      last if $val eq 'ENDOFMIBVIEW';

      if ($val eq 'NOSUCHOBJECT') {
          return Status->error('snmp fatal error - NOSUCHOBJECT');
      }
      if ( $val eq 'NOSUCHINSTANCE' ) {
          return Status->error('snmp fatal error - NOSUCHINSTANCE');
      }

      # Check to see if we've already seen this IID (looping)
      if (defined $seen{$idx} and $seen{$idx}) {
          return Status->error(sprintf 'snmp fatal error - looping at %s', $idx);
      }
      ++$seen{$idx};

      # .1.3.6.1.2.1.25.5.1.1.1.38441 = INTEGER: 40
      printf qq{\%s = \%s: \%s\n}, $idx, ($port ? ($type, $val) : ('BASE64', encode_base64($val, '')))
        unless setting('log') eq 'debug';
  }

  return Status->done(
    sprintf 'completed bulkwalk of %s entries from %s for %s', (scalar keys %seen), ($extra || '.1'), $device->ip);
});

true;
