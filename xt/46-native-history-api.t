#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Basename 'basename';
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
my @ours = ();
File::Find::find({ no_chdir => 1, wanted => sub {
    push @ours, $File::Find::name if -f $File::Find::name and basename($File::Find::name) =~ /^netdisco.*\.js$/;
} }, catdir($root, qw/share public javascripts/));
File::Find::find({ no_chdir => 1, wanted => sub {
    push @ours, $File::Find::name if -f $File::Find::name and /\.tt$/;
} }, catdir($root, qw/share views/));

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
            . "\nanswer with HX-Push-Url or HX-Replace-Url from the route instead";
};

subtest 'mainLayout__after_the_polyfill_went__does_not_load_it' => sub {
    my $main = slurp( catfile($root, qw/share views layouts main.tt/) );
    unlike $main, qr/jquery-history/, 'main.tt does not load jquery-history.js';
    ok !-e catfile($root, qw/share public javascripts jquery-history.js/),
      'the library is not shipped';
};

# htmx now sets the address bar from HX-Push-Url and HX-Replace-Url, and
# answers a back navigation itself. Netdisco keeping its own entries beside
# htmx's would give a single press two meanings, so nothing here may reach for
# the history API at all. The polyfill names above are still checked because a
# site copying old netdisco code is the way they come back.
subtest 'sharedTree__now_htmx_owns_history__touches_no_history_api' => sub {
    my @offenders = ();
    foreach my $file (sort @ours) {
        my $source = slurp($file);
        push @offenders, $file if $source =~ m/\bhistory\.(?:push|replace)State\b/
                               or $source =~ m/\bpopstate\b/
                               or $source =~ m/\bis_from_state_event\b/
                               or $source =~ m/\.deserialize\(/;
    }
    is scalar(@offenders), 0, 'the browser history is left to htmx'
      or diag "still driving history by hand:\n  " . join("\n  ", @offenders)
            . "\nanswer with HX-Push-Url or HX-Replace-Url from the route instead";
};

done_testing;
