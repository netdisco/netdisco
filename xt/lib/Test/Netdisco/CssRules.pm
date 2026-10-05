package Test::Netdisco::CssRules;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw/read_text css_rules css_rule_blocks split_selectors has_color_literal is_guarded/;

our $GUARD      = ':where(:root:not([data-bs-theme]), :root[data-nd-base-layer])';
our $ROOT_GUARD = ':root:where(:not([data-bs-theme]), [data-nd-base-layer])';

my $COLOR = qr/\#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?)\(|\b(?:white|black|red|green|blue|gray|grey|silver|orange|yellow|maroon|navy|purple)\b/i;

sub read_text {
  my $path = shift;
  open my $fh, '<', $path or die "cannot read $path: $!";
  local $/;
  return scalar <$fh>;
}

# Quoted strings are skipped whole: the toast icons are base64 data URIs, and
# a semicolon inside one is not the end of a declaration.
sub css_rules {
  my $css = shift;
  $css =~ s{(/\*.*?\*/)}{ my $c = $1; $c =~ tr/\n/ /c; $c }gse;

  my (@decls, @stack, @ids);
  my $next_id = 0;
  my $start = 0;
  while ($css =~ m/("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[{};])/g) {
    my $token = $1;
    next if length $token > 1;
    my $end = pos($css) - 1;
    my $segment = substr($css, $start, $end - $start);
    my ($lead) = $segment =~ /^(\s*)/;
    my $line = 1 + (substr($css, 0, $start) =~ tr/\n//) + ($lead =~ tr/\n//);

    if ($token eq '{') {
      (my $selector = $segment) =~ s/\s+/ /g;
      $selector =~ s/^ | $//g;
      push @stack, $selector;
      push @ids, $next_id++;
    }
    else {
      if ($segment =~ /:/ and @stack and $stack[-1] !~ /^\@/) {
        my ($property, $value) = split /:/, $segment, 2;
        s/^\s+|\s+$//g for $property, $value;
        $value =~ s/\s+/ /g;
        push @decls, { line => $line, selector => $stack[-1],
                       property => $property, value => $value, rule => $ids[-1] };
      }
      if ($token eq '}') { pop @stack; pop @ids }
    }
    $start = $end + 1;
  }
  return @decls;
}

# Rules in file order, each with its declarations in source order.
sub css_rule_blocks {
  my @blocks;
  my %by_id;
  foreach my $decl (css_rules(shift)) {
    my $block = $by_id{ $decl->{rule} } ||= do {
      my $new = { line => $decl->{line}, selector => $decl->{selector}, decls => [] };
      push @blocks, $new;
      $new;
    };
    push @{ $block->{decls} }, $decl;
  }
  return @blocks;
}

sub split_selectors {
  my $selector = shift;
  my @parts;
  my $depth   = 0;
  my $current = '';
  foreach my $ch (split //, $selector) {
    $depth++ if $ch eq '(';
    $depth-- if $ch eq ')';
    if ($ch eq ',' and $depth == 0) { push @parts, $current; $current = ''; next }
    $current .= $ch;
  }
  push @parts, $current;
  s/^\s+|\s+$//g for @parts;
  return @parts;
}

sub has_color_literal {
  my $value = shift;
  (my $outside_urls = $value) =~ s/url\([^)]*\)//g;
  return $outside_urls =~ $COLOR ? 1 : 0;
}

sub is_guarded {
  my $selector = shift;
  return 1 if $selector eq $ROOT_GUARD;
  foreach my $part (split_selectors($selector)) {
    return 0 unless index($part, "$GUARD ") == 0;
  }
  return 1;
}

1;
