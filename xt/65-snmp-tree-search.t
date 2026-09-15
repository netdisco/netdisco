#!/usr/bin/env perl

use strict;
use warnings;

# Search answers the whole ancestor path as markup, with the tree already open
# down it, in one response. Walking that path a level at a time was the largest
# cost in the browser, and closing it needs no data the route did not have.

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::Snapshot 'render_template';

# Two levels, the first carrying the second as its children, which is the shape
# _get_snmp_data returns when it is given a path to open to.
my ($html, $error) = render_template('ajax/device/snmptree.tt', {
  device => '192.0.2.1',
  nodes => [
    { oid => '.1.3', label => 'org (3)', icon => 'fas fa-folder text-info',
      has_children => 1, open => 1, children => [
        { oid => '.1.3.6', label => 'dod (6)', icon => 'fas fa-folder text-info',
          has_children => 1, open => 1, children => [] },
      ] },
  ],
});
is $error, undef, 'the template renders' or diag $error;

like $html, qr{<details[^>]* open}, 'a node on the path renders already open';
like $html, qr{org \(3\)}, 'the node on the path is there';
# The label sits before the details it belongs to, so that the child list
# inside that details lands beneath the label rather than after it. Nesting is
# the claim, not order: the child has to be inside the parent's own child list.
# Matched on the closing tag of the label's own anchor, not on the bare text:
# the branch's aria-label repeats it, and that sits ahead of the child list in
# either order, so a looser pattern passes whatever the order is.
like $html, qr{org \(3\)</a>.*<ul class="nd_snmp-children">.*dod \(6\)</a>.*</ul>.*</details>}s,
  'and its child is nested inside it, in the same response';

# A node the server filled must not fetch its children again and swap one flat
# level over them, so it carries no fetch at all.
unlike $html, qr{<details[^>]*/snmptree/\.1\.3"}s,
  'a node the search opened does not fetch its children again';

# A node not on the path stays closed and keeps its empty container, so its
# first open still fetches.
my ($closed) = render_template('ajax/device/snmptree.tt', {
  device => '192.0.2.1',
  nodes => [ { oid => '.1.3', label => 'org (3)', icon => 'fas fa-folder text-info',
               has_children => 1, open => 0, children => [] } ],
});
unlike $closed, qr{<details[^>]* open}, 'a node off the path is closed';
like $closed, qr{<ul class="nd_snmp-children">\s*</ul>}, 'with nothing in it yet';
like $closed, qr{hx-trigger="[^"]*\bonce\b}, 'and fetches them at most once';

# A search that matches nothing leaves the tree alone and changes only the
# state icon beside the box. The box aims at the tree, so answering the icon
# alone would blank it, and the route has to say not to swap.
my $route = do { local (@ARGV, $/) = 'lib/App/Netdisco/Web/Plugin/Device/SNMP.pm'; <> };
like $route, qr{header 'HX-Reswap' => 'none';\s*\n\s*return _snmp_state_icon},
  'a miss says not to swap, and answers the icon alone';
like $route, qr{hx-swap-oob="true"}, 'the icon is swapped out of band';


# A search opens the tree to its hit, and the hit has to say which node it is:
# the tree it opens can be hundreds of rows, so an opened path on its own points
# at nothing. Only the node the search matched carries the mark.
my ($marked) = render_template('ajax/device/snmptree.tt', {
  device => '192.0.2.1',
  nodes => [
    { oid => '.1.3', label => 'org (3)', icon => 'fas fa-folder text-info',
      has_children => 1, open => 1, found => 0, children => [
        { oid => '.1.3.6', label => 'dod (6)', icon => 'fas fa-leaf text-info',
          has_children => 0, open => 0, found => 1, children => [] },
      ] },
  ],
});

like $marked, qr{class="nd_snmp-label nd_snmp-found"[^>]*>\s*<i[^>]*></i>dod \(6\)}s,
  'the node the search found is marked';
my @marks = ($marked =~ m/nd_snmp-found/g);
is scalar @marks, 1, 'and it is the only one marked';

done_testing;
