package App::Netdisco::Worker::Plugin::LoadMIBs;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Dancer::Plugin::DBIC 'schema';

use File::Spec::Functions qw(catdir catfile);
use File::Slurper qw(read_lines write_text);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use File::Temp;
# use DDP;

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;

  debug "loadmibs - loading netdisco-mibs object cache";

  my $home = (setting('mibhome') || catdir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'netdisco-mibs'));
  my $infile = catfile($home, qw(EXTRAS reports all_oids));
  my $outfh = File::Temp->new();
  my $outfile = $outfh->filename;
  gunzip $infile => $outfile or die "gunzip failed: $GunzipError\n";
  my @report = read_lines($outfile, 'latin-1');

  my @browser = ();
  my %children = ();

  foreach my $line (@report) {
    my ($oid, $qual_leaf, $type, $access, $index, $status, $enum, $descr) = split m/,/, $line, 8;
    next unless defined $oid and defined $qual_leaf;

    my ($mib, $leaf) = split m/::/, $qual_leaf;
    my @oid_parts = grep {length} (split m/\./, $oid);
    ++$children{ join '.', '', @oid_parts[0 .. (@oid_parts - 2)] }
      if scalar @oid_parts > 1;

    push @browser, {
      oid    => $oid,
      oid_parts => [ @oid_parts ],
      mib    => $mib,
      leaf   => $leaf,
      type   => $type,
      access => $access,
      index  => [($index ? (split m/:/, $index) : ())],
      status => $status,
      enum   => [($enum  ? (split m/:/, $enum ) : ())],
      descr  => $descr,
    };
  }

  foreach my $row (@browser) {
    $row->{num_children} = $children{ $row->{oid} } || 0;
  }

  debug sprintf "loadmibs - loaded %d objects from netdisco-mibs",
    scalar @browser;

  schema('netdisco')->txn_do(sub {
    my $gone = schema('netdisco')->resultset('SNMPObject')->delete;
    debug sprintf 'loadmibs - removed %d oids', $gone;
    schema('netdisco')->resultset('SNMPObject')->populate(\@browser);
    debug sprintf 'loadmibs - added %d new oids', scalar @browser;
  });

  return Status->done('Loaded MIBs');
});

true;
