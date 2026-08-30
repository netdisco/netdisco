#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catfile catdir updir/;
use File::Find ();
use FindBin;

# A SOURCE ASSERTION: whether back and forward work is a browser question, and
# that is checked with Playwright against a running server, not from here.
#
# window.History still exists, as the browser's own interface constructor, so a
# "window.History && ..." guard still passes its first half and a getState()
# call throws rather than reporting an absent object. Hence matching on names.

my $root = catdir( $FindBin::Bin, updir() );

sub slurp {
    my $path = shift;
    open my $fh, '<:encoding(UTF-8)', $path or die "$path: $!";
    local $/; return <$fh>;
}

# netdisco's own scripts and templates only. The vendored libraries beside them
# are third-party bytes and are not ours to assert about.
my @ours = (
    catfile($root, qw/share public javascripts netdisco.js/),
    catfile($root, qw/share public javascripts netdisco_portcontrol.js/),
);
File::Find::find({ no_chdir => 1, wanted => sub {
    push @ours, $File::Find::name if -f $File::Find::name and /\.tt$/;
} }, catdir($root, qw/share views/));
File::Find::find({ no_chdir => 1, wanted => sub {
    push @ours, $File::Find::name if -f $File::Find::name and /\.js$/;
} }, catdir($root, qw/share views js/));

subtest 'sharedTree__after_the_polyfill_went__names_no_window_History' => sub {
    my @offenders = ();
    foreach my $file (sort @ours) {
        my $source = slurp($file);
        push @offenders, $file if $source =~ m/\bwindow\.History\b/
                               or $source =~ m/\bHistory\.Adapter\b/
                               or $source =~ m/\bHistory\.getState\b/;
    }
    is scalar(@offenders), 0, 'nothing reaches for the history.js global'
      or diag "still using window.History:\n  " . join("\n  ", @offenders)
            . "\nuse history.pushState, history.replaceState and the popstate event";
};

subtest 'mainLayout__after_the_polyfill_went__does_not_load_it' => sub {
    my $main = slurp( catfile($root, qw/share views layouts main.tt/) );
    unlike $main, qr/jquery-history/, 'main.tt does not load jquery-history.js';
    ok !-e catfile($root, qw/share public javascripts jquery-history.js/),
      'the library is not shipped';
};

subtest 'tabNavigation__replaying_a_history_entry__still_guards_against_a_loop' => sub {
    # replaying an entry clicks a tab link, so the replay guard has to stay;
    # the guard against pushState firing its own event does not, since the
    # native one fires nothing
    my $netdisco = slurp( catfile($root, qw/share public javascripts netdisco.js/) );
    like $netdisco, qr/\bis_from_state_event\b/, 'the replay guard is still there';
    unlike $netdisco, qr/\bis_from_history_plugin\b/,
      'the guard that only history.js needed is gone';
    like $netdisco, qr/addEventListener\(\s*'popstate'/,
      'back and forward are handled through popstate';
};

done_testing;
