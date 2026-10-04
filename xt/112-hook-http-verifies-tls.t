#!/usr/bin/env perl

use strict; use warnings;
no warnings 'once'; # local *glob = sub {} overrides below are single-use by design

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::Worker::Plugin::Hook::HTTP ();
use HTTP::Tiny;
use MIME::Base64 'encode_base64';
use Dancer qw/:moose :script !pass/;

{
  package FakeJob;
  sub new { my ($class, %vals) = @_; return bless {%vals}, $class }
  sub extra { $_[0]->{extra} }
  sub subaction { return }
  sub is_cancelled { 0 }
  sub is_offline { 0 }
  sub only_namespace { return }
  sub device { return }
}

my $worker = vars->{'workers'}->{'hook'}->{'main'}->{'http'}->{0}->[0];

sub run_hook {
  my ($action_conf) = @_;
  my (%client_args, $client);

  my $orig_new = \&HTTP::Tiny::new;
  local *HTTP::Tiny::new = sub {
    my ($class, %args) = @_;
    %client_args = %args;
    $client = $orig_new->($class, %args);
    return $client;
  };
  local *HTTP::Tiny::request = sub {
    return { success => 1, status => 200, reason => 'OK' };
  };

  my $extra = encode_base64( to_json({
    event_data  => { ip => '192.0.2.1' },
    action_conf => $action_conf,
  }), '' );
  my $status = $worker->( FakeJob->new( extra => $extra ) );

  return ($status, $client, \%client_args);
}

subtest 'hook_http__registered_worker__is_found' => sub {
  is ref $worker, 'CODE', 'the http hook main worker is registered';
};

subtest 'hook_http__insecure_default_unset__builds_client_with_verify_ssl_true' => sub {
  delete local $ENV{PERL_HTTP_TINY_SSL_INSECURE_BY_DEFAULT};
  my ($status, $client, $client_args) = run_hook({
    url          => 'https://hook.example.com/event',
    bearer_token => 'not-a-real-token',
  });

  is $status->status, 'done', 'the hook ran to completion';
  ok $client, 'the hook built an HTTP::Tiny client';
  ok $client_args->{verify_SSL},
    'the hook passes a true verify_SSL to the client';
};

subtest 'hook_http__insecure_default_set_to_one__builds_client_with_verify_ssl_false' => sub {
  local $ENV{PERL_HTTP_TINY_SSL_INSECURE_BY_DEFAULT} = '1';
  my ($status, $client, $client_args) = run_hook({
    url          => 'https://hook.example.com/event',
    bearer_token => 'not-a-real-token',
  });

  is $status->status, 'done', 'the hook ran to completion';
  ok $client, 'the hook built an HTTP::Tiny client';
  ok !$client_args->{verify_SSL},
    'the hook passes a false verify_SSL to the client';
};

subtest 'hook_http__timeout_configured__client_keeps_timeout' => sub {
  my (undef, undef, $client_args) = run_hook({
    url     => 'https://hook.example.com/event',
    timeout => 2500,
  });

  is $client_args->{timeout}, 2.5, 'the configured timeout reaches the client';
};

done_testing;
