package App::Netdisco::Worker::Plugin::CheckEncoding;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::SNMPText
  qw/ scan_config_encoding scan_stored_encoding /;

my $LIMIT_PER_COLUMN = 50;

register_worker({ phase => 'main' }, sub {
  my @config_findings = scan_config_encoding(config());
  my @stored_findings = scan_stored_encoding(schema('netdisco'), $LIMIT_PER_COLUMN);
  my $devices = schema('netdisco')->resultset('Device')->count;

  my $total = scalar @config_findings
    + scalar grep { not exists $_->{more} } @stored_findings;

  if (! $total) {
      return Status->done(sprintf
        'Checked %d device%s and the configuration, nothing to report.',
        $devices, ($devices == 1 ? '' : 's'));
  }

  # print rather than log: this is a report a person asked for, and the log
  # level netdisco-do runs at would suppress it. DumpConfig.pm prints for the
  # same reason.
  print "\n";
  foreach my $finding (@config_findings) {
      printf "configuration %s\n  %s\n  looks like: %s\n\n",
        $finding->{path}, $finding->{value},
        (defined $finding->{suggestion} ? $finding->{suggestion} : '(not recoverable)');
  }

  foreach my $finding (@stored_findings) {
      if (exists $finding->{more}) {
          printf "%s: and %d more\n\n", $finding->{column}, $finding->{more};
      }
      elsif (defined $finding->{suggestion}) {
          printf "%s %s\n  %s\n  looks like: %s\n\n", $finding->{ip},
            $finding->{column}, $finding->{value}, $finding->{suggestion};
      }
      else {
          printf "%s %s\n  %s\n  re-read on next discover, original bytes not recoverable\n\n",
            $finding->{ip}, $finding->{column}, $finding->{value};
      }
  }

  return Status->done(sprintf '%d finding%s.', $total, ($total == 1 ? '' : 's'));
});

true;
