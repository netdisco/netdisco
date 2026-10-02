#!/usr/bin/env perl

use strict;
use warnings;
no warnings 'once'; # the glob overrides below are single-use by design

# The two delete endpoints answered {"deleted":"0E0"} when nothing matched.
# DBI returns "no rows" as the string "0E0" so that it is true, the handlers
# guarded with ($gone || 0), which a true string passes straight through, and
# to_json wrote it as it came. A client comparing deleted to 0 saw a string
# that is neither 0 nor a count.
#
# Only the DB edges are faked: the token, the roles, and the resultset whose
# delete returns what DBI would. The routes and their JSON are the real ones.

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Web;
use App::Netdisco::Web::Auth::Provider::DBIC;
use Dancer ':tests';
use Dancer::Test;

package FakeUser;
sub new      { return bless { username => $_[1] }, $_[0] }
sub username { return $_[0]->{username} }

package FakeRS;
our $ROWS;
sub new    { return bless {}, $_[0] }
sub search { return $_[0] }
sub find   { return bless {}, 'FakeDevice' }
sub delete { return $ROWS }

package FakeSchema;
sub new       { return bless {}, $_[0] }
sub resultset { return FakeRS->new }

package main;

no warnings 'redefine';
*App::Netdisco::Web::Auth::Provider::DBIC::validate_api_token = sub { FakeUser->new('admin') };
*Dancer::Plugin::Auth::Extensible::logged_in_user = sub { return { username => 'admin' } };
*Dancer::Plugin::Auth::Extensible::user_roles = sub {
  my @r = qw/api api_admin admin/; return wantarray ? @r : [@r] };
*App::Netdisco::Web::API::Queue::schema   = sub { FakeSchema->new };
*App::Netdisco::Web::API::Objects::schema = sub { FakeSchema->new };

# see xt/97: Dancer::Test does not reset the cookie jar between requests
sub fresh_request { Dancer::Cookies->init; return dancer_response(@_) }

foreach my $path ('/api/v1/queue/jobs', '/api/v1/object/device/192.0.2.1/jobs') {
  foreach my $case (['0E0' => 0], [3 => 3]) {
    local $FakeRS::ROWS = $case->[0];
    my $res = fresh_request(DELETE => $path, { headers => [
      'Authorization' => 'token', 'Accept' => 'application/json' ] });

    is $res->status, 200, "DELETE $path answers";
    my $data = from_json($res->content);
    is $data->{deleted}, $case->[1], "and counts $case->[1] when DBI says $case->[0]";
    like $res->content, qr/"deleted"\s*:\s*\Q$case->[1]\E\s*[,}]/,
      'as a JSON number, not a string';
  }
}

done_testing;
