#!/usr/bin/env perl

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use File::Temp ();
use File::Path 'make_path';
use File::Spec::Functions 'catfile';

use App::Netdisco;
use App::Netdisco::Backend::Job;
use App::Netdisco::Worker::Plugin::LoadMIBs ();

use Try::Tiny;
use Dancer qw/:moose :script !pass/;
use Dancer::Logger::Capture ();

# Capture rather than print: the guard reports its refusal at error level, so a
# clean run would otherwise show it every time. Subtest 1 reads the trap, which
# is the only coverage of the error() call. DANCER_DEBUG restores the console.
my $CONFIG = config();
$CONFIG->{logger} = ($ENV{'DANCER_DEBUG'} ? 'console' : 'capture');
$CONFIG->{log} = 'debug';
Dancer::Logger->init($CONFIG->{logger}, $CONFIG);

# The schema is replaced with a stand-in that records the statements it is asked
# for and returns nothing, so this file needs no database, like the rest of xt/.
# The blocks after the guard are therefore proved entered, not proved to work.
# ND2_DB_ROLLBACK is not an alternative: Runner.pm opens its transaction guard
# through its own schema, which this does not cover, and the file would then
# need a live server. our() is a lexical alias, so the packages below can use
# @STATEMENTS unqualified.
our @STATEMENTS = ();

# Set by the third subtest to make a block after the guard fail, which is the
# situation the worker's add_status call exists for.
our $BREAK_LATER_BLOCKS = 0;

{
  package FakeResultSet;
  sub new        { bless { name => $_[1] }, $_[0] }
  sub delete     { push @STATEMENTS, "delete $_[0]{name}"; return 0 }
  sub populate   { push @STATEMENTS, "populate $_[0]{name} " . scalar @{ $_[1] }; return 1 }
  sub search     { return $_[0] }
  sub distinct   { return $_[0] }
  sub get_column { return $_[0] }
  sub all        { return () }
  sub count      { return 0 }
}

{
  package FakeSchema;
  sub resultset {
    push @STATEMENTS, "resultset $_[1]";
    die "simulated failure in a later block\n"
      if $BREAK_LATER_BLOCKS and $_[1] eq 'DeviceBrowser';
    return FakeResultSet->new($_[1]);
  }
  sub txn_do    { return $_[1]->() }
}

# The plugin must already be loaded, hence the use above: its own
# "use Dancer::Plugin::DBIC 'schema'" would otherwise install the real schema
# after this assignment and undo it.
{
  no warnings 'redefine';
  *App::Netdisco::Worker::Plugin::LoadMIBs::schema = sub { bless {}, 'FakeSchema' };
}

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

# netdisco-mibs 4.054 onwards ships EXTRAS/reports as git-lfs pointer stubs,
# because GitHub tag archives do not resolve LFS. The files exist and parse to
# nothing, which is the silent case: 4.053 shipped no *_oids files at all, so
# the read dies before ever reaching the guard.
#
# juniper_oids is here so the line count can tell the dedupe apart from dropping
# @maps altogether: without it every file is one of the three hardcoded names
# and both regressions read the same number of lines. It is reached through the
# *_oids glob, so a TMPDIR containing a dot drops it (see LoadMIBs.pm:29) and
# the count assertion fails rather than passing for the wrong reason.
sub mibhome_with_lfs_stubs {
  my $home = File::Temp->newdir();
  my $reports = catfile("$home", 'EXTRAS', 'reports');
  make_path($reports);
  foreach my $report (qw/rfc_oids net-snmp_oids cisco_oids juniper_oids/) {
      open my $fh, '>', catfile($reports, $report) or die $!;
      print {$fh} "version https://git-lfs.github.com/spec/v1\n"
                . "oid sha256:0000000000000000000000000000000000000000000000000000000000000000\n"
                . "size 12345\n";
      close $fh;
  }
  return $home;
}

# A parseable report line: oid, MIB::leaf, type, access, index, status, enum, descr.
sub mibhome_with_valid_reports {
  my $home = File::Temp->newdir();
  my $reports = catfile("$home", 'EXTRAS', 'reports');
  make_path($reports);
  foreach my $report (qw/rfc_oids net-snmp_oids cisco_oids/) {
      open my $fh, '>', catfile($reports, $report) or die $!;
      print {$fh} ".1.3.6.1.2.1.1.1,SNMPv2-MIB::sysDescr,OCTET STRING,"
                . "read-only,,current,,A textual description of the entity\n";
      close $fh;
  }
  return $home;
}

sub run_loadmibs {
  my ($mibhome, $vendor) = @_;
  @STATEMENTS = ();
  config->{'mibhome'} = "$mibhome";
  # subaction, not extra: extra is a read-only alias for it (Job.pm:229) and is
  # not a constructor slot, so Moo drops it and the vendor branch never runs.
  my $job = App::Netdisco::Backend::Job->new({
    job => 0, action => 'loadmibs', ($vendor ? (subaction => $vendor) : ()) });
  try { MyWorker->new()->run($job) } catch { diag "unexpected exception: $_" };
  return $job;
}

subtest 'loadmibs__reports_are_lfs_stubs__refuses_without_deleting' => sub {
    my $job = run_loadmibs( mibhome_with_lfs_stubs() );

    is $job->status, 'error',
      'the job reports failure rather than success'
      or diag $job->log;

    like $job->log, qr/refusing to empty snmp_object/,
      'and says the table was deliberately left alone';

    # error() rather than the status list, because that is the only thing a
    # --quiet operator sees: netdisco-do raises the log level to error, which
    # suppresses both add_status's debug line and its own closing status line.
    SKIP: {
        skip 'console logger in use under DANCER_DEBUG', 1 if $ENV{'DANCER_DEBUG'};
        ok scalar(grep { $_->{level} eq 'error'
                         and $_->{message} =~ m/refusing to empty snmp_object/ }
                  @{ Dancer::Logger::Capture->trap->read }),
          'and logged the refusal at error level';
    }

    # Four files at three lines each, read once. Reverting the dedupe gives 21
    # because the glob repeats the three hardcoded names; dropping @maps gives
    # 9 because juniper_oids is only reachable through the glob.
    like $job->log, qr/\bread 12 lines\b/,
      'each report file was read exactly once';

    # Anchored, so a future line that merely counts the preserved rows does not
    # read as a delete.
    is_deeply [ grep { m/^(?:delete|populate) SNMPObject/ } @STATEMENTS ], [],
      'the load branch never touched snmp_object'
      or diag join "\n", @STATEMENTS;

    # Only the load is skipped. Promotion reads the table the refusal just
    # preserved; the legacy upgrade is unrelated work that should not become
    # collateral damage. The count tells the two blocks apart, which their
    # resultset names cannot, and is one per txn_do block: change it only on
    # purpose.
    is scalar(grep { m/^resultset DeviceBrowser/ } @STATEMENTS), 2,
      'snapshot promotion and the legacy upgrade both still ran'
      or diag join "\n", @STATEMENTS;

    # A stand-in that has fallen behind the worker's resultset calls dies in a
    # later block, and finalise_status prefers the earliest error, so the
    # refusal keeps status and log. Drift in the last stand-in method reaches
    # only this assertion, which is what earns it its place. Vacuous on an empty
    # status list, which the refusal assertion above rules out: the status
    # assertion cannot, because finalise_status falls back to error on an empty
    # list.
    is_deeply [ grep { $_->status eq 'error'
                       and ($_->log // '') !~ m/refusing to empty snmp_object/ }
                @{ $job->_statuslist } ], [],
      'the refusal is the only error, so nothing after the guard failed'
      or diag join "\n", map { $_->log // '' } @{ $job->_statuslist };
};

subtest 'loadmibs__reports_parse_to_objects__does_not_refuse' => sub {
    my $job = run_loadmibs( mibhome_with_valid_reports() );

    is $job->status, 'done',
      'the job succeeds'
      or diag $job->log;

    unlike $job->log, qr/refusing to empty snmp_object/,
      'the guard does not fire when objects were parsed';

    is_deeply [ grep { m/^(?:delete|populate) SNMPObject/ } @STATEMENTS ],
      [ 'delete SNMPObject', 'populate SNMPObject 1' ],
      'the table is replaced, in that order'
      or diag join "\n", @STATEMENTS;
};

# The worker records the refusal as the job's outcome the moment it decides,
# rather than only returning it at the end, because the blocks after the guard
# act on other tables and can fail on their own. Without that, the exception
# below would become the outcome and the refusal would never reach the operator.
subtest 'loadmibs__a_later_block_dies__still_reports_the_refusal' => sub {
    local $BREAK_LATER_BLOCKS = 1;
    my $job = run_loadmibs( mibhome_with_lfs_stubs() );

    like $job->log, qr/refusing to empty snmp_object/,
      'the refusal is the outcome, not the later failure'
      or diag join "\n", map { $_->log // '' } @{ $job->_statuslist };

    ok scalar(grep { ($_->log // '') =~ m/simulated failure/ }
                  @{ $job->_statuslist }),
      'and the later failure was recorded rather than swallowed'
      or diag join "\n", map { $_->log // '' } @{ $job->_statuslist };
};

subtest 'loadmibs__vendor_report_is_an_lfs_stub__refuses_without_deleting' => sub {
    my $job = run_loadmibs( mibhome_with_lfs_stubs(), 'cisco' );

    is $job->status, 'error',
      'the guard covers the single-vendor read as well'
      or diag $job->log;

    # The line count is the only thing that distinguishes this branch from the
    # default one, so without it this subtest silently becomes a duplicate of
    # the first: three lines is cisco_oids alone, twelve is all four files.
    like $job->log, qr/\bread 3 lines\b/,
      'and only the named vendor report was read'
      or diag $job->log;

    is_deeply [ grep { m/^(?:delete|populate) SNMPObject/ } @STATEMENTS ], [],
      'and the load branch never touched snmp_object'
      or diag join "\n", @STATEMENTS;
};

done_testing;
