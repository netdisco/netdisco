#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::Snapshot 'render_template';

# The three sidebars each carried their own copy of this control, and they had
# drifted: one optional and reading a config default, two required and calling
# to_daterange(). One include is what stops them drifting again.
my ($report) = render_template('sidebar/_daterange.tt',
  { all_dates => '1970-01-01 to 2026-09-07', required => 1 });

like $report, qr{<select[^>]*data-nd-daterange}, 'the preset select is there';
like $report, qr{value="all"[^>]*selected}, 'and All dates is what it opens on';
like $report, qr{<div[^>]*nd_daterange-pair[^>]*hidden}, 'with the two fields hidden';
like $report, qr{name="daterange"[^>]*value="1970-01-01 to 2026-09-07"},
  'and the shipped default on the wire';
unlike $report, qr{<input[^>]*type="date"[^>]*min=}, 'no min attribute on a date field';
unlike $report, qr{<span[^>]*nd_daterange-addon[^>]*\bid=},
  'the from/to labels carry no id, so two instances on one page cannot collide';

my ($node) = render_template('sidebar/_daterange.tt', { all_dates => '', required => 0 });
like $node, qr{name="daterange"[^>]*value=""},
  'a page whose filter is optional sends no range at all';

# After a reader searches for Last 7 days, the page re-renders with a narrowed
# current range while all_dates still names the epoch. The label must not
# claim "All dates" for a range that is not all dates.
my ($narrowed) = render_template('sidebar/_daterange.tt', {
  all_dates => '1970-01-01 to 2026-09-07',
  current   => '2026-08-31 to 2026-09-07',
  required  => 1,
});

like $narrowed, qr{value="custom"[^>]*selected}, 'a narrowed range opens on Custom range';
unlike $narrowed, qr{value="all"[^>]*selected}, 'and not on All dates';
unlike $narrowed, qr{<div[^>]*nd_daterange-pair[^>]*hidden},
  'so the pair of fields is shown, not hidden';
like $narrowed, qr{aria-label="From"[^>]*value="2026-08-31"},
  'with the from field filled in';
like $narrowed, qr{aria-label="To"[^>]*value="2026-09-07"},
  'and the to field filled in';

done_testing;
