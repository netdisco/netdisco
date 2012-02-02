#!/usr/bin/env perl

# use lib '/root/perl-profiles/netdisco-web/lib/perl5';
use local::lib '/srv/www/vhosts/netdisco.ecmwf.int/perl-profiles/netdisco-web';
use lib '/srv/www/vhosts/netdisco.ecmwf.int/Netdisco/lib';

use Dancer;
use Netdisco::Web;
dance;
