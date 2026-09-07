#!/usr/bin/env perl

use strict;
use warnings;

# The tree is markup now, so the shape a browser gets is worth asserting here
# rather than only in the browser: a row is a <details> whose <summary> holds
# the disclosure control alone, with the label beside it as a link that fetches
# the detail panel. Those being separate is the whole interface decision, and
# nothing else here would notice them merging.

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::Snapshot 'render_template';

my ($html, $error) = render_template('ajax/device/snmptree.tt', {
  device => '192.0.2.1',
  nodes => [
    { oid => '.1.3', label => 'org (3)', icon => 'fas fa-folder text-info',
      has_children => 1, open => 0, children => [] },
    { oid => '.1.3.6.1.2.1.1.5', label => 'sysName (5)', icon => 'fas fa-leaf text-info',
      has_children => 0, open => 0, children => [] },
  ],
});
is $error, undef, 'the template renders' or diag $error;

like $html, qr{<details}, 'a branch renders as a details element';
like $html, qr{<summary}, 'with a summary for the disclosure control';

# A summary toggles on any click inside it, so a label placed there would
# expand the branch as well as select it. Keeping them apart is what makes the
# two actions stay two actions without any JavaScript.
unlike $html, qr{<summary[^>]*>.*?sysName.*?</summary>}s,
  'the label is not inside the summary';
unlike $html, qr{<summary[^>]*>.*?org \(3\).*?</summary>}s,
  'not for a branch either';

like $html, qr{hx-get="[^"]*/snmpnode/\.1\.3\.6\.1\.2\.1\.1\.5"},
  'the label fetches the detail panel for its own oid';
like $html, qr{<details[^>]*hx-get="[^"]*/snmptree/\.1\.3"}s,
  'a branch fetches its children by its own oid, from the details itself';

# toggle fires on close as well as open, and Chromium fires it for a branch
# that arrives already open, so a branch the server filled must carry no fetch
# at all: one would swap a single flat level over the subtree below it.
my ($prefilled) = render_template('ajax/device/snmptree.tt', {
  device => '192.0.2.1',
  nodes => [
    { oid => '.1.3', label => 'org (3)', icon => 'fas fa-folder text-info',
      has_children => 1, open => 1, children => [
        { oid => '.1.3.6', label => 'dod (6)', icon => 'fas fa-folder text-info',
          has_children => 1, open => 0, children => [] },
      ] },
  ],
});
like $prefilled, qr{dod \(6\)}, 'a filled branch renders its children';
unlike $prefilled, qr{<details[^>]*/snmptree/\.1\.3"}s,
  'and asks for no children of its own';
like $prefilled, qr{<details[^>]*/snmptree/\.1\.3\.6"}s,
  'while the empty branch inside it still does';

# The summary is empty, so the name the reader hears has to come from the
# details element itself.
like $html, qr{<details[^>]*aria-label="Expand org \(3\)"},
  'a branch carries an accessible name';

# A leaf has nothing to expand, so it carries no disclosure control at all.
my ($leaf_only) = render_template('ajax/device/snmptree.tt', {
  device => '192.0.2.1',
  nodes => [ { oid => '.1.3.6.1.2.1.1.5', label => 'sysName (5)',
               icon => 'fas fa-leaf text-info', has_children => 0, open => 0,
               children => [] } ],
});
unlike $leaf_only, qr{<details}, 'a leaf is not wrapped in details';
unlike $leaf_only, qr{/snmptree/}, 'and asks for no children';

done_testing;
