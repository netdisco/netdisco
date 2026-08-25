#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;

# Responses are compressed by Plack::Middleware::Deflater, configured in the
# `plack_middlewares` list in bin/netdisco-web-fg. That list is NOT part of the
# Dancer app, so Dancer::Test cannot see it and the source assertions used by
# xt/35 and xt/36 could not catch the mistake that matters most here: Static
# short-circuits, so a Deflater placed below it in the list never sees a static
# asset and silently compresses nothing.
#
# So this file drives the real PSGI app through Plack::Test. It can, where
# xt/35 and xt/36 could not, because a static asset is served by the middleware
# stack without ever reaching a route, so none of the `require_role` handlers
# and none of the DBIC auth provider are involved. App::Netdisco::Web sets
# session_cookie_key when HARNESS_ACTIVE is true, which is what makes the app
# loadable in a test process at all.

BEGIN {
  # Plack::Test needs these before the app is loaded, and the app refuses to
  # build without a public directory for Plack::Middleware::Static.
  $ENV{DANCER_PUBLIC} ||= catdir($FindBin::Bin, updir(), 'share', 'public');
}

use Plack::Test;
use Plack::Util;
use HTTP::Request::Common;
use IO::Uncompress::Gunzip 'gunzip';
use File::Temp;

my $psgi = catfile($FindBin::Bin, updir(), 'bin', 'netdisco-web-fg');
my $app  = eval { Plack::Util::load_psgi($psgi) };

# Never skip. A skip here would hide the whole feature, which is the failure
# mode xt/36 warns about: green locally, never run upstream.
BAIL_OUT("could not load $psgi: $@") unless $app;

my $JS   = '/javascripts/portsort.js';
my $PNG  = '/images/favicon.ico';
my $ondisk = do {
  open my $fh, '<:raw', catfile($ENV{DANCER_PUBLIC}, 'javascripts', 'portsort.js')
    or BAIL_OUT("cannot read portsort.js: $!");
  local $/; <$fh>;
};

test_psgi $app, sub {
  my $cb = shift;

  subtest 'staticAsset__clientAcceptsGzip__isCompressedAndInflatesToTheFile' => sub {
    my $res = $cb->(GET $JS, 'Accept-Encoding' => 'gzip');
    is $res->code, 200, 'the asset is served';
    is $res->header('Content-Encoding'), 'gzip', 'the response is gzip encoded';
    like $res->header('Vary'), qr/\bAccept-Encoding\b/,
      'Vary names Accept-Encoding so a shared cache keys on it';

    my $body = $res->content;
    cmp_ok length($body), '<', length($ondisk),
      'the compressed body is smaller than the file';

    # Assert the magic bytes before inflating. IO::Uncompress::Gunzip can
    # succeed on input that was never compressed, so "it inflates" alone would
    # pass against a response that lost its encoding entirely.
    is substr($body, 0, 2), "\x1f\x8b", 'the body begins with the gzip magic';

    my $inflated = '';
    ok gunzip(\$body => \$inflated), 'the body inflates';
    is $inflated, $ondisk, 'and inflates to exactly the bytes on disk';
  };

  subtest 'staticAsset__clientDoesNotAcceptGzip__isServedVerbatim' => sub {
    my $res = $cb->(GET $JS);
    is $res->code, 200, 'the asset is served';
    is $res->header('Content-Encoding'), undef, 'no Content-Encoding is set';
    is $res->content, $ondisk, 'the body is the file, byte for byte';
  };

  subtest 'alreadyCompressedType__clientAcceptsGzip__isNotCompressedAgain' => sub {
    my $res = $cb->(GET $PNG, 'Accept-Encoding' => 'gzip');
    is $res->code, 200, 'the image is served';
    is $res->header('Content-Encoding'), undef,
      'an image is left alone: it is already compressed, so gzip is pure cost';
  };

  # The regex in the Expires middleware named application/javascript, while
  # Plack::MIME serves .js as text/javascript, so every JavaScript file went
  # out with no cache header at all. That is the larger half of the page
  # payload by bytes. Guard both halves of the pair.
  subtest 'staticAsset__anyCacheableType__carriesAnExpiresHeader' => sub {
    for my $u ($JS, '/css/netdisco.css', $PNG) {
      my $res = $cb->(GET $u);
      ok $res->header('Expires'), "$u carries an Expires header";
    }
  };
};

# The middleware list is built once, when the app is loaded, so the setting
# cannot be flipped inside the process above. Drive a second interpreter with
# the override that #1592 added, and assert the operator's off switch really
# reaches the middleware list rather than merely existing in the config.
subtest 'compressResponses__settingIsFalse__nothingIsCompressed' => sub {
  my $probe = <<'PROBE';
use Plack::Util; use Plack::Test; use HTTP::Request::Common;
my $app = Plack::Util::load_psgi($ARGV[0]);
test_psgi $app, sub { my $cb = shift;
  my $r = $cb->(GET '/javascripts/portsort.js', 'Accept-Encoding' => 'gzip');
  print 'ENCODING=', ($r->header('Content-Encoding') // 'none'), "\n";
};
PROBE

  # Via a file, not perl -e: the probe contains single quotes, and shell
  # quoting them wrong yields an empty result that looks like a clean pass.
  my $fh = File::Temp->new(SUFFIX => '.pl');
  print {$fh} $probe;
  close $fh;

  local $ENV{NETDISCO_WITH_CONFIGURATION} = '{"compress_responses":false}';
  local $ENV{HARNESS_ACTIVE} = 1;
  my $lib = catdir($FindBin::Bin, updir(), 'lib');
  my $out = qx{$^X -I"$lib" "$fh" "$psgi" 2>/dev/null};

  # Guard against the probe dying and leaving $out empty, which would make the
  # negative assertion below pass for the wrong reason.
  like $out, qr/^ENCODING=/m, 'the probe ran and reported an encoding';

  like $out, qr/^ENCODING=none$/m,
    'with compress_responses false the asset is served uncompressed';
};

# The static assets above cannot produce a text/xml response, and driving one
# needs a populated database, so this is a source assertion. It is here because
# the type was missing from the first version of the list and nothing caught it:
# 87 routes across 18 files are declared with Dancer::Plugin::Ajax's `ajax`
# keyword, which defaults the content type to text/xml rather than text/html,
# and those fragments are the largest responses Netdisco sends. Measured on a
# 7300 port device, one of them is 2,184,560 bytes, compressing to 18,875.
subtest 'compressibleTypes__ajaxFragments__areCoveredByTheList' => sub {
  open my $fh, '<', $psgi or BAIL_OUT("cannot read $psgi: $!");
  my $src = do { local $/; <$fh> };
  my ($list) = $src =~ m/my \@compressible = qw\((.*?)\)/s;
  ok $list, 'the compressible list is where this test expects it';
  like $list, qr{\btext/xml\b},
    'text/xml is listed, or every ajax fragment silently goes uncompressed';
};

done_testing;
