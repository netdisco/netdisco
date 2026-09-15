#!/usr/bin/env perl

use strict;
use warnings;

# Proves App::Netdisco::Template::Plugin::CSV neutralizes formula-triggering
# cells without touching legitimate numbers, and, separately, that its
# registration actually reaches a rendered template rather than merely that
# the class exists: that second property is why the render-path subtest
# below is not redundant with the direct calls above it.
#
# Text::CSV->new() here carries no `binary` option (matching the CPAN
# plugin's own constructor, which this module does not override), so a
# field containing a raw carriage return already fails to combine at all,
# before and after this fix. That case is therefore outside what dump() can
# demonstrate; it is not exercised below for that reason, not because the
# neutralization rule treats it differently from a leading tab.

BEGIN { $ENV{DANCER_ENVIRONMENT} = 'testing'; }

use Test::More 0.88;
use Template::Plugin::CSV;
use App::Netdisco::Template::Plugin::CSV;

use App::Netdisco;
use App::Netdisco::Web;
use Dancer qw/:syntax :tests/;
use Dancer::Test;

subtest 'dump__formula_trigger_that_is_not_a_number__gets_apostrophe_prefixed' => sub {
  my $csv = App::Netdisco::Template::Plugin::CSV->new(undef);

  is $csv->dump(['=1+1']), q{'=1+1}, 'leading = is neutralized';
  is $csv->dump(['+cmd']), q{'+cmd}, 'leading + is neutralized';
  is $csv->dump(['@cmd']), q{'@cmd}, 'leading @ is neutralized';
  is $csv->dump(['-1+cmd']), q{'-1+cmd},
    'a leading minus that only starts like a number is neutralized';
  is $csv->dump(['-']), q{'-}, 'a bare minus sign is not a number either';

  # Text::CSV itself wraps a field containing a tab in double quotes
  # (quote_space); the leading apostrophe this module adds is still the
  # first character inside those quotes.
  is $csv->dump(["\tcmd"]), qq{"'\tcmd"}, 'a leading tab is neutralized';
};

subtest 'dump__a_negative_number__is_left_alone' => sub {
  my $csv = App::Netdisco::Template::Plugin::CSV->new(undef);

  is $csv->dump(['-64']),   '-64',   'a negative integer is unchanged';
  is $csv->dump(['-64.5']), '-64.5', 'a negative decimal is unchanged';
  is $csv->dump(['64']),    '64',    'an unsigned integer is unchanged';
  is $csv->dump(['64.5']),  '64.5',  'an unsigned decimal is unchanged';
};

subtest 'dump__whitespace_around_a_number__is_still_neutralized_where_it_matters' => sub {
  my $csv = App::Netdisco::Template::Plugin::CSV->new(undef);

  # Trailing whitespace is deliberately not part of "a valid number" here:
  # netdisco never emits a padded numeric value (Perl's own number
  # stringification never does), so treating "-64 " as exempt would only
  # ever benefit a value shaped to look numeric while carrying more than a
  # number. The safe reading wins over the lenient one.
  is $csv->dump(['-64 ']), qq{"'-64 "},
    'trailing whitespace after a number does not exempt it';

  # A leading plain space is not one of the trigger characters (a
  # spreadsheet's own formula detection looks at the cell's actual first
  # character, not the first non-space one), so it is left alone.
  is $csv->dump([' -64']), q{" -64"},
    'leading plain whitespace before a number is not itself a trigger';

  # A leading tab is a trigger regardless of what follows it, including
  # something that would otherwise read as a plain number.
  is $csv->dump(["\t-64"]), qq{"'\t-64"},
    'a leading tab in front of a number is still neutralized';
};

subtest 'dump__an_ordinary_string_or_undef__is_unchanged' => sub {
  my $csv = App::Netdisco::Template::Plugin::CSV->new(undef);

  is $csv->dump(['switch-name']), 'switch-name', 'a plain string is unchanged';
  is $csv->dump(['']), '', 'an empty string is unchanged';
  is $csv->dump([undef]), '', 'undef does not warn and is unchanged';
};

subtest 'dump_values__hash_argument__is_neutralized_the_same_way' => sub {
  my $csv = App::Netdisco::Template::Plugin::CSV->new(undef);
  my $out = $csv->dump_values({ a => '=1+1', b => '-64' });

  like $out, qr/'=1\+1/, 'a formula trigger inside dump_values is prefixed';
  like $out, qr/(?<!')-64\b/, 'and a negative number inside it keeps no prefix';
};

subtest 'TemplatePluginCSV__the_unpatched_upstream_plugin__does_not_neutralize' => sub {
  # Confirms the difference above is attributable to registering our
  # subclass, not to something Text::CSV does on its own.
  my $upstream = Template::Plugin::CSV->new(undef);
  is $upstream->dump(['=1+1']), '=1+1',
    'the CPAN plugin passes a formula trigger straight through';
};

# The render-path proof: a route that renders a real shipped *_csv.tt
# template exactly the way a report route does (CSV content type, no_auth so
# no database-backed session is needed), through the full Dancer dispatch
# cycle, so Web.pm's AUTO_FILTER hooks and share/config.yml's PLUGINS
# registration are both live, not simulated.
setting('no_auth' => 1);

get '/ajax/xt-csv-formula-probe' => sub {
  header('Content-Type' => 'text/comma-separated-values');
  template 'ajax/report/nodesdiscovered_csv.tt', {
    results => [ {
      dns         => '=CMD_TRIGGER',
      port        => '+PLUS_TRIGGER',
      remote_id   => '-64',
      remote_ip   => '-64.5',
      remote_port => '-1+NOTNUM',
      remote_type => 'ordinary hostname',
    } ],
  }, { layout => 'noop' };
};

subtest 'renderedTemplate__csv_dump_through_the_real_app__neutralizes_without_touching_numbers' => sub {
  my $response = dancer_response(GET => '/ajax/xt-csv-formula-probe');
  is $response->status, 200, 'the probe route renders successfully';

  my $body = $response->content;

  like $body, qr/'=CMD_TRIGGER,'\+PLUS_TRIGGER,/,
    'the = and + triggers both come out with an apostrophe prefix';
  like $body, qr/,-64,-64\.5,/,
    'the negative integer and negative decimal columns are untouched, still adjacent';
  like $body, qr/'-1\+NOTNUM,"ordinary hostname"/,
    'a leading minus that is not a whole number is prefixed, and the plain string after it is not';
};

done_testing;
