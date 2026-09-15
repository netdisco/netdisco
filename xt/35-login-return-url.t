#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catfile updir/;
use FindBin;

# AuthN.pm's first `before` hook fills in return_url so that a user bounced to
# the login form is sent back where they were heading. Its rule is "if you are
# not on the front page, come back to where you are", which is right everywhere
# except the one page you leave by using it: a bare POST /login set return_url
# to /login, so a successful login redirected to the login page.
#
# It does not lock a browser user out, who reaches the app on the next request,
# but a client that reads the redirect target concludes it failed and discards
# a session that actually works. Measured before the fix: correct password gave
# 302 to /login, wrong password gave 200, so the two were already
# distinguishable by status; it is the target that lied.
#
# Fixed by treating /login the way / is already treated, so both fall through to
# web_home. That reuses the answer netdisco already gives in the two places it
# answers this question: this hook, and the /logout redirect further down the
# same file. Nothing new is asserted about where users belong.
#
# THIS FILE IS A SOURCE ASSERTION, and that is a real limitation rather than a
# shortcut. A request-level test would be better. What puts it out of reach is
# the database, and only the database: the app itself loads here, provided
# `use App::Netdisco;` comes first, Dancer::Test works, and GET /login answers
# 200. But every protected route goes through the DBIC auth provider, which
# setting `no_auth` does not bypass, since that only names the user `guest` and
# still resolves it against the database. So the login POST this file is about
# cannot be driven from xt.
#
# Do not close that gap by finding a database at run time and skipping without
# one. A developer machine has one and CI does not, so the test would look green
# here and never run upstream, which is how the phantomjs QUnit page went
# unnoticed for years.
#
# The behavioural evidence is five journeys driven through a browser against a
# real instance, recorded in the commit that added this file. What is asserted
# here is the property that made the defect possible, so that a later edit
# reverting it is caught.

my $authn = catfile( $FindBin::Bin, updir(),
    'lib', 'App', 'Netdisco', 'Web', 'AuthN.pm' );

my $source = do {
    open my $fh, '<', $authn or die "cannot read $authn: $!";
    local $/;
    <$fh>;
};

# The hook is the first one in the file and ends at the first closing brace on
# its own line. Anchoring on it rather than searching the whole file matters:
# the second `before` hook forty lines below legitimately mentions the login
# path too, and asserting against the file as a whole would pass on that alone
# while this hook had been reverted.
my ($hook) = $source =~ m/(hook \s+ 'before' \s+ => \s+ sub \s* \{ .*? ^\};)/msx;

subtest 'authN__return_url_default__is_anchored_on_the_first_before_hook' => sub {
    ok defined $hook && length $hook, 'the first before hook was located'
        or diag 'the hook was not found, so every assertion below is vacuous';
    like $hook, qr/return_url/, 'and it is the hook that sets return_url';
    unlike $hook, qr/logout/,
        'and not the session hook below it, which names logout';
};

subtest 'authN__bare_login_post__does_not_return_the_user_to_the_login_page' => sub {
    like $hook, qr{uri_for\('/login'\)->path},
        'the login path is excluded from the "come back here" default, so a '
      . 'successful login falls through to web_home instead of /login';
};

subtest 'authN__protected_page__still_returns_there_after_login' => sub {
    # The feature the hook exists for, and the thing the fix could plausibly
    # have broken. Both halves have to survive: the request URI is still the
    # default for ordinary paths, and web_home is still the fallback.
    like $hook, qr/request->uri/,
        'an ordinary path still defaults to the page the user asked for';
    like $hook, qr/uri_for\(setting\('web_home'\)\)->path/,
        'and the fallback is still web_home rather than a hardcoded path';
};

subtest 'authN__explicit_return_url__is_still_honoured' => sub {
    # ||= rather than =, so a caller that supplies return_url keeps it. An
    # earlier draft of this fix could have overwritten it.
    like $hook, qr/params->\{return_url\}\s*\|\|=/,
        'the default only fills in when the caller supplied nothing';
};

done_testing;
