#!/usr/bin/perl
use strict;
use warnings;

use Test::More;
use Env::Path;
use FindBin qw( $Bin );

my $phantomjs = $ENV{ND_PHANTOMJS};

if ( !defined $phantomjs or !-x $phantomjs ) {
    plan skip_all =>
        "phantomjs not found, please set ND_PHANTOMJS to the location of the phantomjs executable";
}
else {
    exec( $phantomjs, "$Bin/js/run_qunit.js", "$Bin/html/portsort.html" );
}
