#!/usr/bin/perl
use strict;
use warnings;

use Test::More;
use Env::Path;
use FindBin qw( $Bin );

my @phantomjs = Env::Path->PATH->Whence('phantomjs');
my $phantomjs = scalar @phantomjs ? $phantomjs[0] : $ENV{ND_PHANTOMJS};

if ( ! defined $phantomjs or !-x $phantomjs ) {
    plan skip_all =>
        "phantomjs not found, please set ND_PHANTOMJS or install phantomjs to the default location";
}
else {
    exec( $phantomjs, "$Bin/js/run_qunit.js", "$Bin/html/portsort.html" );
}
