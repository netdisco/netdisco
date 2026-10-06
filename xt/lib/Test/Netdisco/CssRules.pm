package Test::Netdisco::CssRules;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw/read_text css_rules css_rule_blocks split_selectors has_color_literal is_classic_scoped/;

our $CLASSIC_SCOPE = ':where([data-bs-theme="classic"])';
our $CLASSIC_ROOT  = '[data-bs-theme="classic"]';

my $NAMED_COLORS = join '|', qw/aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blue blueviolet brown burlywood cadetblue chartreuse chocolate coral cornflowerblue cornsilk crimson cyan darkblue darkcyan darkgoldenrod darkgray darkgreen darkgrey darkkhaki darkmagenta darkolivegreen darkorange darkorchid darkred darksalmon darkseagreen darkslateblue darkslategray darkslategrey darkturquoise darkviolet deeppink deepskyblue dimgray dimgrey dodgerblue firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray green greenyellow grey honeydew hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon lightseagreen lightskyblue lightslategray lightslategrey lightsteelblue lightyellow lime limegreen linen magenta maroon mediumaquamarine mediumblue mediumorchid mediumpurple mediumseagreen mediumslateblue mediumspringgreen mediumturquoise mediumvioletred midnightblue mintcream mistyrose moccasin navajowhite navy oldlace olive olivedrab orange orangered orchid palegoldenrod palegreen paleturquoise palevioletred papayawhip peachpuff peru pink plum powderblue purple rebeccapurple red rosybrown royalblue saddlebrown salmon sandybrown seagreen seashell sienna silver skyblue slateblue slategray slategrey snow springgreen steelblue tan teal thistle tomato turquoise violet wheat white whitesmoke yellow yellowgreen/;

my $COLOR = qr/\#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?)\(|(?<![\w-])(?:$NAMED_COLORS)(?![\w-])|^\d+(?:\.\d+)?\s*,\s*\d+(?:\.\d+)?\s*,\s*\d+(?:\.\d+)?$/i;

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

sub is_classic_scoped {
  my $selector = shift;
  foreach my $part (split_selectors($selector)) {
    next if $part eq $CLASSIC_ROOT;
    return 0 unless index($part, "$CLASSIC_SCOPE ") == 0;
  }
  return 1;
}

1;
