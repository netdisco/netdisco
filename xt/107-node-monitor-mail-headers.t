#!/usr/bin/env perl

# Node monitor mail carries device properties in its Subject. Each header is
# printed on one line, followed by the one blank line that ends the headers.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVIRONMENT} = 'testing' }

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Util::NodeMonitor;

my $DOMAIN = 'netdisco.example.test';
my $TO = 'noc@example.test';

sub header_lines {
  my $block = join '', App::Netdisco::Util::NodeMonitor::_headers(@_);
  like $block, qr/\n\n\z/, 'headers end with one blank line';
  $block =~ s/\n\n\z//;
  return split /\n/, $block, -1;
}

subtest '_headers__plain_values__are_printed_unchanged' => sub {
  my @headers = App::Netdisco::Util::NodeMonitor::_headers(
    $TO, 'Saw mac 00:00:5e:00:53:01 (lab) on sw1 Gi1/0/1', $DOMAIN);

  is_deeply \@headers, [
    "To: noc\@example.test\n",
    "From: Netdisco <netdisco\@netdisco.example.test>\n",
    "Subject: Saw mac 00:00:5e:00:53:01 (lab) on sw1 Gi1/0/1\n\n",
  ], 'each header is its own printed string';
};

subtest '_headers__subject_with_line_breaks__keeps_one_subject_line' => sub {
  foreach my $break ("\n", "\r\n", "\r", "\n\n") {
    my @lines = header_lines(
      $TO, "Saw mac 00:00:5e:00:53:01 (lab) on sw1${break}Bcc: x\@example.test Gi1/0/1",
      $DOMAIN);

    is scalar @lines, 3, 'three header lines';
    is $lines[2], 'Subject: Saw mac 00:00:5e:00:53:01 (lab) on sw1 Bcc: x@example.test Gi1/0/1',
      'the line break becomes one space';
    is scalar(grep { m/\r/ } @lines), 0, 'no carriage return remains';
  }
};

subtest '_headers__recipient_with_line_break__keeps_one_to_line' => sub {
  my @lines = header_lines("noc\@example.test\nBcc: x\@example.test", 'Saw mac', $DOMAIN);

  is scalar @lines, 3, 'three header lines';
  is $lines[0], 'To: noc@example.test Bcc: x@example.test', 'the line break becomes one space';
};

subtest '_headers__ordinary_values__are_unchanged' => sub {
  is join(q{}, App::Netdisco::Util::NodeMonitor::_headers(
        'noc@example.com', 'Saw mac 00:11:22:33:44:55 on sw1 Gi1/0/1', 'example.com')),
     "To: noc\@example.com\n"
     ."From: Netdisco <netdisco\@example.com>\n"
     ."Subject: Saw mac 00:11:22:33:44:55 on sw1 Gi1/0/1\n\n",
     'the three headers are unchanged';
};

done_testing;
