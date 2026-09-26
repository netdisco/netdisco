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

sub csv_route_templates {
  my @found;
  File::Find::find({ no_chdir => 1, wanted => sub {
    return unless -f $File::Find::name and $File::Find::name =~ m/\.pm\z/;
    my $source = read_text($File::Find::name);
    while ($source =~ m/$CSV_ROUTE/g) {
      push @found, { file => $File::Find::name, template => $1 };
    }
  } }, 'lib/App/Netdisco/Web');
  return @found;
}

subtest 'csvRoutes__every_one_in_the_web_tree__renders_a_csv_template' => sub {
  my @routes = csv_route_templates();
  # 35 on 2026-09-26; the floor stops a pattern that matches nothing passing.
  cmp_ok scalar @routes, '>=', 30, 'the scan finds the CSV routes';
  my @wrong = grep { $_->{template} !~ m/_csv\.tt\z/ } @routes;
  is_deeply [ map { "$_->{file}: $_->{template}" } @wrong ], [],
    'no CSV route renders a template that is not a *_csv.tt';
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
