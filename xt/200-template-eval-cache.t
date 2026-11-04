#!/usr/bin/env perl

# evaltt_cached must give what evaltt gives, read the stash of each call, and
# compile a text once; Web.pm and externallinks.tt must use it.

use strict;
use warnings;

use Test::More 0.88;
use Template;
use Template::Provider;
use App::Netdisco::Template::Filter::EvalCache;

my $FILTERS = {
  evaltt_cached => [ \&App::Netdisco::Template::Filter::EvalCache::factory, 1 ],
};

sub render {
  my ($engine, $text, $vars) = @_;
  my $out = '';
  $engine->process(\$text, $vars, \$out) or die $engine->error;
  return $out;
}

my $stock  = Template->new({ PRE_CHOMP => 1 });
my $cached = Template->new({ PRE_CHOMP => 1, FILTERS => $FILTERS });

# the shape of externallinks.tt: a URL in config, with variables set per port
my $url  = 'https://mon.example/[% device %]/[% port %]';
my $page = '[% FOREACH p IN ports %][% port = p FILTER uri %][% link.url | evaltt %]|[% END %]';
my $vars = { device => '10.0.0.1', link => { url => $url },
             ports => [ 'Gi1/0/1', 'Gi1/0/2', 'Po1' ] };

(my $page_cached = $page) =~ s/\| evaltt/| evaltt_cached/;
is render($cached, $page_cached, $vars), render($stock, $page, $vars),
  'evaltt_cached gives what evaltt gives, a variable set per port included';

# TT's own filters are not replaced
is render($cached, '[% t | evaltt %]', { t => '[% x %]', x => 'a' }), 'a', 'evaltt is still the stock filter';
is render($cached, '[% t | eval %]',   { t => '[% x %]', x => 'a' }), 'a', 'and so is eval';

# each call reads the stash as it is then, not as it was when the text was first compiled
my $first  = render($cached, '[% link.url | evaltt_cached %]', { device => 'one', port => 'p', link => { url => $url } });
my $second = render($cached, '[% link.url | evaltt_cached %]', { device => 'two', port => 'q', link => { url => $url } });
is $first,  'https://mon.example/one/p', 'first call';
is $second, 'https://mon.example/two/q', 'a later call sees its own variables, not the first one\'s';

# compiled once: count what the provider is asked to compile
{
  my $compiles = 0;
  no warnings 'redefine';
  my $orig = \&Template::Provider::_compile;
  local *Template::Provider::_compile = sub { $compiles++; goto &$orig };

  my $engine = Template->new({ FILTERS => $FILTERS });
  my $text = 'unique-' . $$ . ' [% n %]';
  my $page2 = '[% FOREACH n IN [1 .. 50] %][% text | evaltt_cached %][% END %]';
  render($engine, $page2, { text => $text });

  # one compile for the page, one for the evaluated text, however many ports
  cmp_ok $compiles, '<=', 2, 'fifty evaluations of one text compile it once';
}

# a text that does not compile throws each time and is not kept
{
  my $held = App::Netdisco::Template::Filter::EvalCache::_held();
  my $engine = Template->new({ FILTERS => $FILTERS });
  for (1 .. 2) {
    my $out = '';
    ok !$engine->process(\'[% t | evaltt_cached %]', { t => '[% IF %]' }, \$out), 'a bad text is an error';
  }
  is App::Netdisco::Template::Filter::EvalCache::_held(), $held, 'and it is not remembered';
}

# the table does not grow without end
{
  local $App::Netdisco::Template::Filter::EvalCache::LIMIT = 5;
  my $engine = Template->new({ FILTERS => $FILTERS });
  render($engine, '[% t | evaltt_cached %]', { t => "text $_" }) for 1 .. 20;
  cmp_ok App::Netdisco::Template::Filter::EvalCache::_held(), '<=', 5, 'the held texts stay within the limit';
  is render($engine, '[% t | evaltt_cached %]', { t => 'text 3' }), 'text 3', 'and one dropped is compiled again';
}

# the web application registers it under its own name, and the links use it
{
  open my $fh, '<', 'lib/App/Netdisco/Web.pm' or die "Web.pm: $!";
  my $source = do { local $/; <$fh> };
  like $source, qr/FILTERS\}\s*=\s*\{\s*evaltt_cached\s*=>[^}]*EvalCache::factory/s,
    'Web.pm registers the cached filter as evaltt_cached, and only that';
  unlike $source, qr/FILTERS\}\s*=\s*\{[^}]*\beval(?:tt)?\s*=>/s, 'without replacing eval or evaltt';
  open my $tt, '<', 'share/views/externallinks.tt' or die "externallinks.tt: $!";
  my $links = do { local $/; <$tt> };
  like $links, qr/link\.url \| evaltt_cached/, 'externallinks.tt uses it';
  unlike $links, qr/\| evaltt\b(?!_)/, 'and no longer the compiling filter';
}

done_testing;
