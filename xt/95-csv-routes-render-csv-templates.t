#!/usr/bin/env perl

# A route that answers text/comma-separated-values must render a *_csv.tt
# template: the HTML view sent as CSV arrives as markup with no data, and it
# also bypasses the CSV plugin that neutralizes formula cells.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVIRONMENT} = 'testing'; }

use Test::More 0.88;
use File::Find ();
use File::Slurper 'read_text';

use App::Netdisco;
use App::Netdisco::Web;
use Dancer qw/:syntax :tests/;
use Dancer::Test;

my $CSV_ROUTE = qr{
  header\(\s*['"]Content-Type['"]\s*=>\s*['"]text/comma-separated-values['"]\s*\);
  \s*template\s+['"]([^'"]+)['"]
}x;

# Every mention of the CSV content type has to be read by the pattern, so a
# route written in any other shape fails here instead of passing unchecked.
sub csv_route_problems {
  my ($file, $source) = @_;
  my @problems;
  my $mentions = () = $source =~ m{text/comma-separated-values}g;
  my $matched = 0;
  while ($source =~ m/$CSV_ROUTE/g) {
    $matched++;
    push @problems, "$file: renders $1" unless $1 =~ m/_csv\.tt\z/;
  }
  push @problems, "$file: ". ($mentions - $matched)
    ." CSV response(s) in a shape this test cannot read"
    if $mentions != $matched;
  return @problems;
}

subtest 'csvRoutes__every_one_in_the_web_tree__renders_a_csv_template' => sub {
  my ($routes, @problems) = (0);
  File::Find::find({ no_chdir => 1, wanted => sub {
    return unless -f $File::Find::name and $File::Find::name =~ m/\.pm\z/;
    my $source = read_text($File::Find::name);
    $routes += () = $source =~ m/$CSV_ROUTE/g;
    push @problems, csv_route_problems($File::Find::name, $source);
  } }, 'lib/App/Netdisco/Web');
  # a floor, so a scan that finds nothing cannot pass
  cmp_ok $routes, '>=', 30, 'the scan finds the CSV routes';
  is_deeply \@problems, [],
    'every CSV route renders a *_csv.tt template, in a shape this test reads';
};

subtest 'csvRouteScan__a_csv_response_in_an_unrecognized_shape__is_reported' => sub {
  my $source = "header 'Content-Type' => 'text/comma-separated-values';\n"
             . "template 'ajax/report/x.tt';\n";
  my @problems = csv_route_problems('Synthetic.pm', $source);
  is scalar @problems, 1, 'a CSV response the pattern cannot read is a problem, not a pass';
};

setting('no_auth' => 1);

get '/ajax/xt-vlanmultiplenames-csv-probe' => sub {
  header('Content-Type' => 'text/comma-separated-values');
  template 'ajax/report/vlanmultiplenames_csv.tt', {
    results => [ { vlan => 10, description => [qw/staff users/],
                   dcount => 2, pcount => 5 } ],
  }, { layout => 'noop' };
};

subtest 'vlanMultipleNamesCsv__one_vlan_with_two_names__is_a_csv_row' => sub {
  my $response = dancer_response(GET => '/ajax/xt-vlanmultiplenames-csv-probe');
  is $response->status, 200, 'the probe route renders successfully';
  my $body = $response->content;
  like $body, qr/^"VLAN ID","VLAN Names","Device Count","Port Count"$/m,
    'the heading row is CSV';
  like $body, qr/^10,"staff,users",2,5$/m, 'the data row carries both names';
  unlike $body, qr/<table|<script/, 'no HTML markup reaches the download';
};

done_testing;
