package App::Netdisco::Worker::Plugin::CheckSiteLocal;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::SiteLocal qw/ site_local_paths scan_site_local /;

register_worker({ phase => 'main' }, sub {
  my @paths = site_local_paths();

  if (! scalar @paths) {
      return Status->done('No site-local template paths are configured.');
  }

  my @findings = scan_site_local({ paths => \@paths });

  if (! scalar @findings) {
      return Status->done(sprintf 'Checked %d path%s, nothing to report.',
        scalar @paths, (scalar @paths == 1 ? '' : 's'));
  }

  my %files = map {($_->{path} => 1)} @findings;

  # print rather than log: this is a report a person asked for, and the log
  # level netdisco-do runs at would suppress it. DumpConfig.pm prints for the
  # same reason.
  print "\n";
  foreach my $finding (@findings) {
      printf "%s line %d\n", $finding->{path}, $finding->{line};
      printf "  %s\n", $finding->{excerpt};
      printf "  removed in %s: %s\n\n",
        $finding->{release}, $finding->{advice};
  }

  return Status->done(sprintf '%d finding%s in %d file%s.',
    scalar @findings, (scalar @findings == 1 ? '' : 's'),
    scalar (keys %files), (scalar (keys %files) == 1 ? '' : 's'));
});

true;
