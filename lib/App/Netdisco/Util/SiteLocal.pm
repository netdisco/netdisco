package App::Netdisco::Util::SiteLocal;

use strict;
use warnings;

use File::Find ();

use Dancer ':syntax';
use Path::Class qw/dir file/;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ scan_site_local scan_shadowed_files
                     site_local_rules site_local_paths /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::SiteLocal - find site-local files broken by shipped changes

=head1 DESCRIPTION

Site-local templates override shipped ones by relative path, so they keep
calling APIs that later releases removed. Most of the removals below fail
silently in the browser, which is why this exists: nothing else reports them.

Detection only. This module never writes to a file and never logs.

=cut

# One row per shipped removal. A later rung adds a row here and nothing else.
#
# `pattern` is matched against each line of each file under the scanned paths.
# `release` is the release that removed or deprecated the thing, for the report
# to cite.
my @RULES = (
  {
    name    => 'he-js',
    release => '2.105002',
    pattern => qr/\bhe\s*\.\s*(?:encode|decode)\s*\(/,
    advice  => 'he.js was removed. Use DataTable.util.escapeHtml(), which is '
             . 'loaded on every page already.',
  },
  {
    name    => 'history-js',
    release => '2.105004',
    # History with a capital H is history.js. The browser's own object is
    # lowercase, so the case distinction is the whole test. window.History
    # still exists after the removal, as the DOM interface constructor, so a
    # site's `window.History && ...` guard stops running its branch and never
    # throws. That silence is why this rule matters more than it looks.
    pattern => qr/\bHistory\s*\.\s*(?:pushState|replaceState|getState|Adapter|enabled|log)\b/,
    advice  => 'history.js was removed, and the browser no longer drives '
             . 'the address bar at all. Let the pane response say where it '
             . 'went, with an HX-Push-Url or HX-Replace-Url header, and drop '
             . 'the history call and any popstate listener beside it.',
  },
  {
    name    => 'natural-js',
    release => '2.105004',
    # Both the registered sort-type names and the two ways a DataTables column
    # asks for one. A column asking for a type nothing registers falls back to
    # string sorting, so the rows are quietly in the wrong order.
    #
    # The key's own quotes are optional because both spellings are common: a
    # JSON-shaped config writes "sType", a JavaScript object literal writes
    # sType bare, and a pattern requiring one silently misses the other.
    pattern => qr/natural-(?:asc|desc)\b|["']?(?:type|sType)["']?\s*:\s*["']natural["']/,
    advice  => 'natural.js was removed. Use a built-in DataTables type, or '
             . 'the portsort or versionsort plug-ins netdisco still ships.',
  },
  {
    name    => 'do-search',
    release => '2.105006',
    # The only rule here whose subject still works: do_search forwards to htmx
    # rather than throwing, so a site that ignores this keeps loading its tab.
    # Reported anyway, because the console notice only reaches whoever opens
    # devtools.
    pattern => qr/\bdo_search\s*\(/,
    advice  => 'do_search() now only forwards to htmx and will be removed in a '
             . 'future release. Give the form the hx-get, hx-target, hx-headers, '
             . 'hx-indicator and hx-sync attributes that share/views/device.tt '
             . 'uses, '
             . 'then drop the do_search call from the submit handler.',
  },
  {
    name    => 'datatabledefaults-include',
    release  => '2.109000',
    pattern => qr/INCLUDE\s+['"]ajax\/datatabledefaults\.tt['"]/,
    advice  => 'ajax/datatabledefaults.tt was removed. Delete the INCLUDE and '
             . 'move the table options into the data-nd-table attribute, as '
             . 'share/views/ajax/device/ports.tt now does.',
  },
  {
    name    => 'has-sidebar-global',
    release  => '2.109000',
    pattern => qr/has_sidebar\s*\[/,
    advice  => 'the has_sidebar global was removed. The sidebar visibility '
             . 'marker is now a hidden input carrying data-nd-has-sidebar '
             . 'for the tab and a 0 or 1 value, as '
             . 'share/views/sidebar/report/portlog.tt shows.',
  },
  {
    name    => 'page-script-include',
    release  => '2.109000',
    pattern => qr/INCLUDE\s+['"]js\//,
    advice  => 'share/views/js/ was removed. The page scripts now live in '
             . 'share/public/javascripts/netdisco.js and a template must not '
             . 'include a script; re-copy the template from this release.',
  },
  {
    name    => 'portcontrol-js-renamed',
    release  => '2.109000',
    pattern => qr/netdisco_portcontrol\.js/,
    advice  => 'netdisco_portcontrol.js was renamed netdisco-portcontrol.js '
             . 'and a reference to the old name 404s. Update the script tag '
             . 'to the new file name.',
  },
  {
    name    => 'nd-submit',
    release  => '2.109000',
    pattern => qr/\bnd_submit\s*\(/,
    advice  => 'nd_submit() was removed. Ask htmx to submit the form, with '
             . 'htmx.trigger(\'#ports_form\', \'submit\'), which is what every '
             . 'shipped caller now does.',
  },
  {
    name    => 'page-title-globals',
    release  => '2.109000',
    # data-nd-title and its dataset spelling are here rather than in a file
    # rule because a layout keeping the attribute is harmless; only reading it
    # is broken, and a site-local layout is where the read usually lives.
    pattern => qr/\bupdate_page_title\s*\(|\bdefault_pgtitle\b|\bndTitle\b|data-nd-title/,
    advice  => 'the page title now arrives as a <title> element at the top of '
             . 'the pane response and nothing in the browser sets it. Delete '
             . 'the call, and delete data-nd-title from a layout copy: no '
             . 'shipped code reads it.',
  },
  {
    name    => 'history-replay',
    release  => '2.109000',
    pattern => qr/\bupdate_browser_history\s*\(|\bis_from_state_event\b/,
    advice  => 'the browser no longer records or replays the search history. '
             . 'A pane response says where it went with an HX-Push-Url or '
             . 'HX-Replace-Url header and Back refetches that address, so '
             . 'delete the call and the replay flag beside it.',
  },
  {
    name    => 'jquery-deserialize',
    release  => '2.109000',
    # The plugin shipped for one caller, the popstate replay, so a site naming
    # either the file or the method is running that replay by hand.
    pattern => qr/jquery-deserialize\.js|\.\s*deserialize\s*\(/,
    advice  => 'jquery-deserialize.js was removed with the history replay it '
             . 'was loaded for. Delete the script tag from a layout copy and '
             . 'the .deserialize() call from the handler: Back now refetches '
             . 'the page and the form comes back filled in from the server.',
  },
  {
    name    => 'csv-download-link',
    release  => '2.109000',
    pattern => qr/\bupdate_csv_download_link\s*\(|data-nd-csv\b|\bndCsv\b/,
    advice  => 'the CSV download link now arrives with the pane as an '
             . 'hx-swap-oob anchor and the browser no longer rebuilds it. '
             . 'Delete the call and the data-nd-csv attribute from a sidebar '
             . 'form copy, and keep the id nd_csv-download on the anchor so '
             . 'the response has somewhere to land.',
  },
  {
    name    => 'htmx-abort-trigger',
    release  => '2.109000',
    # anchored on the trigger rather than the event name: the vendored htmx
    # bundle listens for this event, so a site keeping its own copy of that
    # file would otherwise be told to change the library
    pattern => qr/trigger\s*\(\s*[^)]*['"]htmx:abort['"]/,
    advice  => 'a tab form no longer owns its own request, so triggering '
             . 'htmx:abort on one cancels nothing. Give each sidebar form '
             . 'hx-sync="closest .nd_sidebar:replace" and delete the trigger: '
             . 'htmx then cancels the request the tab being left started.',
  },
  {
    name    => 'datatables-js-renamed',
    release  => '2.109000',
    pattern => qr/jquery\.dataTables\.min\.js/,
    advice  => 'jquery.dataTables.min.js was renamed dataTables.min.js, the '
             . 'library no longer needing jQuery, and a reference to the '
             . 'old name 404s. Update the script tag in a layout copy to the '
             . 'new file name: nothing else loads the library, so until then '
             . 'no table on any page builds.',
  },
  {
    name    => 'floatthead-js',
    release  => '2.109000',
    # The file name and the method, because the two break differently: a
    # layout copy still loading the plug-in 404s, and a script still calling
    # it throws once the plug-in is not there to define the method.
    pattern => qr/jquery\.floatThead\.js|\.\s*floatThead\s*\(/,
    advice  => 'jquery.floatThead.js was removed and the stylesheet holds the '
             . 'header still instead. Delete the script tag from a layout copy '
             . 'and the .floatThead() call beside the table, and give that '
             . 'table the class nd_floatinghead: netdisco.css sticks the '
             . 'header of a table.nd_floatinghead inside the tab content, '
             . 'which is what the job queue now relies on.',
  },
  {
    name    => 'jquery-ui-autocomplete',
    release  => '2.109000',
    # Both the constructor and the method form, since a copy that only calls
    # the method still throws once the library is gone.
    # the call alone, not the class the widget adds: a site keeping its own
    # copy of the library would otherwise be told to change the library, and
    # both the minified script and its stylesheet carry that class. A site
    # stylesheet overriding it is left unreported, which is cosmetic; a layout
    # copy still loading the theme is caught by the rule below.
    pattern => qr/\.\s*autocomplete\s*\(/,
    advice  => 'jQuery UI was removed. A field asks for suggestions in its '
             . 'markup now: give the input a data-nd-typeahead attribute '
             . 'holding the endpoint path, with data-nd-typeahead-min, '
             . '-params, -open and -first beside it, and delete the script.',
  },
  {
    name    => 'jquery-ui-removed',
    release  => '2.109000',
    # A copied layout names the script and the theme on two separate lines,
    # and both 404 silently rather than reporting anything.
    pattern => qr{jquery-ui(?:\.min)?\.(?:js|css)|css/smoothness/},
    advice  => 'jquery-ui.min.js and the smoothness theme were removed. Drop '
             . 'both lines from your copy of the layout.',
  },
  {
    name    => 'jstree-removed',
    release => '2.109000',
    # the container, the selector that reaches it, and the vendored path. Not
    # the bare method call: the library contains that itself, in its own jQuery
    # bridge, so matching it told a site keeping a copy to change the library.
    # Measured against the real minified file, which this pattern does not hit.
    pattern => qr{id=["']jstree["']|["']\#jstree["']|javascripts/jstree/},
    advice  => 'jsTree was removed and the SNMP browser is rendered by the '
             . 'server. A copy of the pane should hold a ul#nd_snmp-tree that '
             . 'includes ajax/device/snmptree.tt; delete the container, the '
             . 'script and stylesheet lines from a layout copy, and any '
             . 'jstree() call.',
  },
  {
    name    => 'daterangepicker-removed',
    release => '2.109000',
    # The three file names together, since a copied layout loses each on its
    # own line, and the call, since a script keeping it throws once the
    # library is gone. Measured against the library's own source, which does
    # not carry this call form: it names itself only inside namespaced event
    # strings such as click.daterangepicker, never as a call.
    pattern => qr{javascripts/(?:moment\.min|daterangepicker)\.js
                  |css/daterangepicker\.css
                  |\.\s*daterangepicker\s*\(}x,
    advice  => 'moment.js, daterangepicker.js and daterangepicker.css were '
             . 'removed. Give the field a container like '
             . 'share/views/sidebar/_daterange.tt and delete the '
             . '.daterangepicker() call and the two script tags and the '
             . 'stylesheet link from a layout copy: netdisco-daterange.js '
             . 'drives the control now, so add a script tag for it to the '
             . 'layout copy in their place.',
  },
  {
    name    => 'moment-removed',
    release => '2.109000',
    # The rule above catches a layout still loading the file; this catches the
    # call, since moment was a global on every page for a decade and a site
    # script formatting a date with it throws once the library is gone. The
    # vendored DataTables render helper of the same name as the second
    # alternative requires moment or luxon internally, so a table column
    # configured with it now fails with neither present.
    pattern => qr/\bmoment\s*\(|DataTable\.render\.datetime\s*\(/,
    advice  => 'moment.js was removed and nothing replaces it as a global. '
             . 'Format the date with native Date or Intl.DateTimeFormat '
             . 'instead of calling moment, and give a datetime column a '
             . 'different render function: the DataTable.render.datetime '
             . 'helper needs moment or luxon and neither is loaded any more.',
  },
  {
    name    => 'daterange-input-id',
    release => '2.109000',
    # A site that only customized the sidebar markup never wrote a
    # .daterangepicker() call or named a removed script, so the two rules
    # above stay quiet and this id is the only trace left to catch. The id
    # and the type="text" that went with it sit on different lines in the
    # old markup, so the id alone is the anchor rather than the pair on one
    # line. No shipped template sets this id any more.
    pattern => qr/id=["']daterange["']/,
    advice  => 'this field carried the daterangepicker widget by its id, '
             . 'which is gone along with the JavaScript that drove it, so '
             . 'the field is now a plain text box with nothing behind it. '
             . 'Replace it with a copy of share/views/sidebar/_daterange.tt: '
             . 'netdisco-daterange.js drives the control from its markup, '
             . 'not by id.',
  },
  {
    name    => 'toastr-removed',
    release => '2.109000',
    # Anchored on the call rather than toastr.options, which the library's own
    # source reads from itself, so a site keeping a copy of the library is not
    # told to change the library.
    pattern => qr{javascripts/toastr\.js|css/toastr\.css
                  |toastr\s*\.\s*(?:error|success|info|warning)\s*\(}x,
    advice  => 'toastr was removed. Use ndToast (success, error and info) '
             . 'instead: delete the toastr.js script and toastr.css '
             . 'stylesheet lines from a layout copy and add a script tag '
             . 'for netdisco-toast.js in their place.',
  },
  {
    name    => 'jquery-removed',
    release => '2.109000',
    # Anchored on the exact vendored file name, not a generic jquery*.js glob,
    # so a site's own copy of jquery-ui.min.js or jquery.dataTables.min.js is
    # left to the rule that already covers it. And on the literal jQuery
    # global rather than the bare dollar sign: the widget rules above each
    # anchor on their own call and would report the same line twice, and a
    # template commonly prints a dollar amount or an ES6 template literal,
    # neither of which names the library. A call written only as $(...) for
    # something none of the widget rules name is not caught here.
    pattern => qr{javascripts/jquery-latest(?:\.min)?\.js|\bjQuery\b},
    advice  => 'jQuery must not appear in a site-local script or a copied '
             . 'layout. Delete the script line naming jquery-latest.min.js '
             . 'from a layout copy, and rewrite a jQuery call with native '
             . 'DOM methods: netdisco-request.js carries the request and '
             . 'form helpers the shipped scripts use.',
  },
);

# Rules that fault what a file does NOT contain, so a finding has no line.
#
# `startup` marks the ones the web application warns about at every worker
# boot. The bar is that nothing else tells anyone: a shadowed tab page renders
# an empty pane in silence and a shadowed layout kills every page. The rest
# degrade something the person can see going wrong, and a warning on every boot
# for those is noise a site cannot turn off.
my @FILE_RULES = (
  {
    name     => 'tab-page-shadow',
    release  => '2.105006',
    startup  => 1,
    paths    => [qw/ device.tt search.tt report.tt /],
    requires => qr/\bhx-get\b/,
    advice   => 'this copy predates the htmx tab transport, so its sidebar '
              . 'form never fetches the pane and the tab renders empty. Copy '
              . 'the hx-get, hx-target, hx-headers and hx-indicator attributes '
              . 'from the shipped template of the same name.',
  },
  {
    name     => 'layout-shadow',
    release  => '2.109000',
    startup  => 1,
    paths    => ['layouts/main.tt'],
    requires => qr/data-nd-uri-base/,
    advice   => 'this copy predates data-nd-uri-base and the other body '
              . 'attributes that carry the page JavaScript settings, so '
              . 'netdisco.js throws reading them and every page is dead. '
              . 'Re-copy layouts/main.tt from this release and re-apply the '
              . 'local branding: it now carries those settings as body '
              . 'attributes and loads the scripts at the end of the body.',
  },
  {
    name     => 'csv-download-target',
    release  => '2.109000',
    paths    => [qw/ device.tt search.tt report.tt admintask.tt /],
    requires => qr/nd_csv-download/,
    advice   => 'this copy carries no element with the id nd_csv-download, so '
              . 'the download link the pane response now sends alongside the '
              . 'results has nothing to swap into and the page reports the '
              . 'miss to the console instead of offering a download. Copy the '
              . 'anchor carrying that id from the shipped template of the same '
              . 'name.',
  },
  {
    name     => 'sidebar-reset-target',
    release  => '2.109000',
    paths    => ['device.tt'],
    requires => qr/nd_sidebar-reset-link/,
    advice   => 'this copy carries no element with the id '
              . 'nd_sidebar-reset-link, so the Reset to Defaults link the '
              . 'Ports and Network Map panes now send alongside the results '
              . 'has nothing to swap into. Copy the anchor carrying that id '
              . 'from the shipped device.tt.',
  },
  {
    name     => 'tab-sync-attribute',
    release  => '2.109000',
    paths    => [qw/ device.tt search.tt report.tt admintask.tt /],
    requires => qr/\bhx-sync\b/,
    advice   => 'this copy predates hx-sync, so leaving a tab whose results '
              . 'are still loading neither cancels that request nor takes its '
              . 'loading indicator down, and the answer can arrive over the '
              . 'tab moved to. Add hx-sync="closest .nd_sidebar:replace" '
              . 'beside the hx-get on each sidebar form.',
  },
);

=head2 scan_shadowed_files( \%args )

Returns a finding for each file under C<< $args{paths} >> that shadows one of
one of the shipped tab pages without carrying what that page needs.

A finding is a hashref with keys C<kind> (always C<file>), C<path>, C<rule>,
C<release> and C<advice>. There is no C<line>: the fault is an absence, so
there is no line to point at.

C<< $args{rules} >> optionally restricts the scan to the named rules.
C<< $args{startup} >> restricts it to the rules the web application warns
about at every worker boot, which is how L<App::Netdisco::Web> asks for them:
the rest are for the person who ran C<checksitelocal> and asked.

Bounded on purpose. This opens at most one file per shipped tab page per
configured path, because L<App::Netdisco::Web> runs it at every worker startup,
where C<scan_site_local>'s walk of the whole tree would not be welcome.

=cut

sub scan_shadowed_files {
  my $args = shift || {};
  my @paths = @{ $args->{paths} || [] };
  my @findings = ();

  my %wanted = map {($_ => 1)} @{ $args->{rules} || [] };
  my @rules = (keys %wanted)
    ? (grep { $wanted{ $_->{name} } } @FILE_RULES) : @FILE_RULES;
  @rules = grep { $_->{startup} } @rules if $args->{startup};

  foreach my $rule (@rules) {
      foreach my $relative (@{ $rule->{paths} }) {
          foreach my $path (@paths) {
              next unless defined $path and length $path;
              my $shadow = file($path, $relative)->stringify;
              next unless -f $shadow;
              next if _file_contains($shadow, $rule->{requires});
              push @findings, {
                kind    => 'file',
                path    => $shadow,
                rule    => $rule->{name},
                release => $rule->{release},
                advice  => $rule->{advice},
              };
          }
      }
  }

  # sort returns undef in scalar context, not a count
  my @sorted = sort { $a->{path} cmp $b->{path} } @findings;
  return @sorted;
}

sub _file_contains {
  my ($file, $pattern) = @_;
  open my $fh, '<', $file or return 0;
  while (my $line = <$fh>) {
      next unless $line =~ $pattern;
      close $fh;
      return 1;
  }
  close $fh;
  return 0;
}

=head2 site_local_rules

Returns the rule table as a list of hashrefs with keys C<name>, C<release> and
C<advice>. Lists what is checked without scanning anything.

=cut

sub site_local_rules {
  return map {; +{ name => $_->{name}, release => $_->{release},
                   advice => $_->{advice} } } (@RULES, @FILE_RULES);
}

=head2 site_local_paths

Returns the directories a scan should cover: C<template_paths> from
C<deployment.yml>, plus the two C<nd-site-local> directories when
C<site_local_files> is on.

These are the same directories L<App::Netdisco::Web> unshifts onto the Template
Toolkit C<INCLUDE_PATH>. Derived here rather than passed in, so the
C<checksitelocal> action and the web app's startup check cannot drift apart.

The shipped C<share/views> is deliberately absent: it is what site-local files
override, not something to scan.

=cut

sub site_local_paths {
  my @paths = ();
  my $configured = setting('template_paths');
  push @paths, @$configured if $configured and ref [] eq ref $configured;

  if (setting('site_local_files')) {
      my $home = ($ENV{NETDISCO_HOME} || $ENV{HOME});
      push @paths,
        dir($home, 'nd-site-local', 'share')->stringify,
        dir($home, 'nd-site-local', 'share', 'views')->stringify;
  }

  return @paths;
}

=head2 scan_site_local( \%args )

Scans every file under each directory in C<< $args{paths} >> and returns the
findings, sorted by path then line. C<< $args{rules} >> optionally restricts the
scan to the named rules.

A finding is a hashref with keys C<path>, C<line>, C<rule>, C<release>,
C<excerpt> and C<advice>.

A directory that does not exist is skipped rather than fatal: C<template_paths>
routinely names directories a given install has not created.

=cut

sub scan_site_local {
  my $args = shift || {};
  my @paths = @{ $args->{paths} || [] };

  my %wanted = map {($_ => 1)} @{ $args->{rules} || [] };
  my @rules = (keys %wanted)
    ? (grep { $wanted{ $_->{name} } } @RULES) : @RULES;
  return () unless scalar @rules;

  # site_local_paths returns nd-site-local/share and nd-site-local/share/views,
  # and the second is inside the first, so every file below views is reached
  # twice. Read each file once, keyed on the name File::Find gives it.
  my %seen = ();
  my @findings = ();

  foreach my $path (@paths) {
      next unless defined $path and length $path and -d $path;
      File::Find::find({ no_chdir => 1, wanted => sub {
          return unless -f $File::Find::name;
          return if $seen{ $File::Find::name }++;
          push @findings, _scan_file($File::Find::name, \@rules);
      }}, $path);
  }

  # Assigned rather than returned straight from sort, which yields undef in
  # scalar context instead of a count.
  my @sorted =
    sort { $a->{path} cmp $b->{path} or $a->{line} <=> $b->{line} } @findings;

  return @sorted;
}

# Read once, test every rule against every line. A line can match more than one
# rule and each match is its own finding, because each carries its own advice.
# The line number is counted here rather than read from $., which is not reset
# between files and would number the second file from where the first ended.
sub _scan_file {
  my ($file, $rules) = @_;

  open my $fh, '<', $file or return ();
  my @findings = ();
  my $lineno = 0;

  while (my $line = <$fh>) {
      $lineno++;
      chomp $line;
      foreach my $rule (@$rules) {
          next unless $line =~ $rule->{pattern};
          my $excerpt = $line;
          $excerpt =~ s/^\s+|\s+$//g;
          push @findings, {
            path    => $file,
            line    => $lineno,
            rule    => $rule->{name},
            release => $rule->{release},
            excerpt => $excerpt,
            advice  => $rule->{advice},
          };
      }
  }
  close $fh;

  return @findings;
}

1;
