package App::Netdisco::DB::StepFile;

use strict;
use warnings;

use Carp ();

use base 'Exporter';
our @EXPORT_OK = qw(
  parse_step_file legacy_statements inline_comment_lines step_file_path
);

my $NO_TRANSACTION_DIRECTIVE = '-- netdisco: no-transaction';

sub step_file_path {
  my ($share_dir, $from) = @_;
  return sprintf '%s/App-Netdisco-DB-%d-%d-PostgreSQL.sql', $share_dir, $from, $from + 1;
}

sub _slurp {
  my $path = shift;
  open my $fh, '<', $path or Carp::croak("Cannot read schema step file $path: $!");
  local $/;
  my $text = <$fh>;
  close $fh;
  return $text;
}

# Single left-to-right scan. Returns [ kind, text ] pairs where kind is one of
# code, string, dollar, comment or split. Comment text excludes its newline.
sub _tokenize {
  my $sql = shift;
  my @tokens;
  pos($sql) = 0;
  while (pos($sql) < length $sql) {
    if ($sql =~ /\G(--[^\n]*)/gc) { push @tokens, [comment => $1] }
    elsif ($sql =~ /\G('(?:[^']|'')*'?)/gc) { push @tokens, [string => $1] }
    elsif ($sql =~ /\G(\$[A-Za-z_]*\$)/gc) { push @tokens, [dollar => _dollar_body(\$sql, $1)] }
    elsif ($sql =~ /\G;/gc) { push @tokens, [split => ';'] }
    else { $sql =~ /\G([^-';\$]+|.)/gcs; push @tokens, [code => $1] }
  }
  return \@tokens;
}

# An unterminated dollar quote swallows the rest of the file, as Postgres would.
sub _dollar_body {
  my ($sql_ref, $opening_tag) = @_;
  my $start = pos($$sql_ref);
  my $close_at = index($$sql_ref, $opening_tag, $start);
  my $end = $close_at < 0 ? length $$sql_ref : $close_at + length $opening_tag;
  my $body = $opening_tag . substr($$sql_ref, $start, $end - $start);
  pos($$sql_ref) = $end;
  return $body;
}

sub parse_step_file {
  my $path = shift;
  my $text = _slurp($path);
  my ($first_line) = split /\n/, $text, 2;
  $first_line = '' unless defined $first_line;
  $first_line =~ s/\s+$//;

  my (@statements, $current);
  $current = '';
  foreach my $token (@{ _tokenize($text) }) {
    my ($kind, $chunk) = @$token;
    next if $kind eq 'comment';
    if ($kind eq 'split') {
      push @statements, $current;
      $current = '';
      next;
    }
    $current .= $chunk;
  }
  push @statements, $current;

  return {
    no_transaction => ($first_line eq $NO_TRANSACTION_DIRECTIVE ? 1 : 0),
    statements => [ _meaningful(@statements) ],
  };
}

sub _meaningful {
  return grep { length && !/^(?:BEGIN|BEGIN TRANSACTION|COMMIT)$/i }
    map { s/^\s+//r =~ s/\s+$//r } @_;
}

# Must stay byte-for-byte what DBIx::Class::Schema::Versioned::_read_sql_file
# does: it is the fallback for steps below the baseline, which ran this way.
sub legacy_statements {
  my $path = shift;
  my @lines = split /\n/, _slurp($path);
  return [ split /;/, join '', grep {
    $_ && !/^--/ && !/^(BEGIN|BEGIN TRANSACTION|COMMIT)/mi
  } @lines ];
}

sub inline_comment_lines {
  my $path = shift;
  my ($line, $code_on_line, @reported) = (1, 0);
  foreach my $token (@{ _tokenize(_slurp($path)) }) {
    my ($kind, $chunk) = @$token;
    push @reported, $line if $kind eq 'comment' && $code_on_line;
    next if $kind eq 'comment';
    my $newlines = () = $chunk =~ /\n/g;
    if ($newlines) {
      $line += $newlines;
      $code_on_line = ($chunk =~ /\n([^\n]*)\z/)[0] =~ /\S/ ? 1 : 0;
    }
    else {
      $code_on_line ||= $chunk =~ /\S/ ? 1 : 0;
    }
  }
  return \@reported;
}

1;
