#!/usr/bin/env perl

# xt/bin/regenerate-snapshots renders every template in share/views to refresh
# xt/snapshots/. f21cceb0 gave Test::Netdisco::Snapshot's engine a PLUGINS
# mapping to App::Netdisco::Template::Plugin::CSV, but the script only ever put
# xt/lib on its own include path, never the distribution's lib/. Every
# *_csv.tt template has failed to render under the script ever since, though
# the script still prints "wrote N snapshots" and exits 1, which reads as
# success to anyone not checking the exit code.
#
# ./Build test cannot see this: Module::Build puts blib/lib on @INC, and on
# PERL5LIB, for the whole test run, and PERL5LIB is inherited by any
# subprocess. So the module is findable there whatever the script's own @INC
# says. A test that simply requires App::Netdisco::Template::Plugin::CSV, or
# calls render_template in this process, proves nothing about the script.
#
# So this guard reruns the script's own include-path setup, verbatim, in a
# child process launched with PERL5LIB and friends cleared, and asks that
# child to render one *_csv.tt template. That reproduces the environment a
# developer actually runs the script in, not the suite's own.

use strict;
use warnings;

use Test::More 0.88;
use FindBin;
use Path::Class 'dir';
use File::Temp 'tempfile';
use Cwd qw/getcwd abs_path/;

my $root       = dir($FindBin::RealBin)->parent;
my $script_dir = $root->subdir('xt', 'bin');
my $script     = $script_dir->file('regenerate-snapshots');

my $source = do {
    open my $fh, '<', $script or BAIL_OUT("cannot read $script: $!");
    local $/;
    <$fh>;
};

# Everything up to and including this line is the script's own @INC setup
# plus the module load it exists to enable. Slicing there, rather than
# retyping the setup here, means a future change to how the script finds
# lib/ is exercised as it actually is, not as this guard assumes it to be.
my ($preamble) = $source =~ /\A(.*^use Test::Netdisco::Snapshot .*?;\n)/ms;
ok(defined $preamble, 'found the script\'s own @INC setup to reuse verbatim')
    or BAIL_OUT("xt/bin/regenerate-snapshots no longer matches the pattern "
        . "this guard slices on; update the pattern in xt/86-snapshot-regenerator.t");

my $probe = $preamble . <<'PROBE';
my ($html, $error) = render_template('ajax/search/device_csv.tt');
if (defined $error) { print "ERROR:$error"; exit 0 }
print "OK:" . length($html);
PROBE

# Written alongside the real script, not under /tmp: the preamble's own
# FindBin::RealBin (unshifting parent->parent->subdir('lib') onto @INC) has
# to resolve from xt/bin the same way it does for the real script, or this
# guard would test its own tempdir's ancestry instead of the fix.
my ($fh, $filename) = tempfile(SUFFIX => '.pl', DIR => $script_dir->stringify, UNLINK => 1);
print {$fh} $probe;
close $fh;

my $original_cwd = getcwd();
# The script assumes it runs from the repository root, the same way a
# developer would invoke it (xt/bin/regenerate-snapshots), so the child needs
# the same working directory for its relative 'xt/lib' and share/views paths
# to resolve.
chdir $root or BAIL_OUT("cannot chdir to $root: $!");

my $output = do {
    # Module::Build sets PERL5LIB to include blib/lib for this whole test
    # run, and a child process inherits it like any other environment
    # variable. Without removing it here, the child would find the CSV
    # plugin via blib no matter what the script itself puts on @INC, which
    # is exactly the blind spot xt/40-template-snapshots.t already has.
    #
    # Only the entries leading back into this distribution go: its lib, blib
    # and xt/lib, whichever the runner happened to add. Clearing these
    # variables outright also removes the path to netdisco's dependencies
    # wherever they are installed into a local::lib, which is how the
    # container CI runs in is built, and the child could then not load Dancer
    # at all.
    my $root_abs = abs_path($root->stringify);
    my $strip = sub {
        return join ':', grep {
            my $abs = abs_path($_);
            not (defined $abs and defined $root_abs and index($abs, $root_abs) == 0)
        } grep { length } split m/:/, (shift // '');
    };
    local $ENV{PERL5LIB} = $strip->($ENV{PERL5LIB});
    local $ENV{PERLLIB}  = $strip->($ENV{PERLLIB});
    delete local $ENV{PERL5OPT};
    open my $ph, '-|', $^X, $filename
        or BAIL_OUT("cannot run $filename: $!");
    local $/;
    my $captured = <$ph>;
    close $ph;
    diag("child perl exited $?") if $?;
    $captured;
};

chdir $original_cwd or BAIL_OUT("cannot chdir back to $original_cwd: $!");

subtest 'regenerateSnapshotsScript__csvTemplateUnderItsOwnIncludePath__renders' => sub {
    like($output, qr/^OK:\d+\z/,
        q{the CSV plugin loads and the template renders under the script's own include path, not the suite's})
      or diag("child produced: $output");
};

done_testing;
