package Test::Netdisco::Snapshot;

use strict;
use warnings;

use File::Find ();
use File::Spec;
use Template::AutoFilter;

use base 'Exporter';
our @EXPORT_OK = qw/render_template all_templates snapshot_path stash_for
                    VIEW_ROOT SNAPSHOT_ROOT/;

use constant VIEW_ROOT     => 'share/views';
use constant SNAPSHOT_ROOT => 'xt/snapshots';

# Mirrors share/config.yml:1005-1015. If that block changes, change this.
sub _engine {
  return Template::AutoFilter->new({
    INCLUDE_PATH => [ VIEW_ROOT ],
    START_TAG    => quotemeta('[%'),
    END_TAG      => quotemeta('%]'),
    ANYCASE      => 1,
    ABSOLUTE     => 1,
    PRE_CHOMP    => 1,
    AUTO_FILTER  => 'html_entity',
    ENCODING     => 'utf8',
  });
}

=head2 all_templates

Sorted list of every C<.tt> under C<share/views>, relative to that directory.

=cut

sub all_templates {
  my @found = ();
  # no_chdir is load-bearing: without it File::Find chdirs into each directory
  # while $File::Find::name stays relative to the start, so the -f test is
  # evaluated against the wrong path and matches nothing.
  File::Find::find({ no_chdir => 1, wanted => sub {
    return unless -f $File::Find::name and $File::Find::name =~ m/\.tt$/;
    my $rel = File::Spec->abs2rel($File::Find::name, VIEW_ROOT);
    push @found, $rel;
  } }, VIEW_ROOT);
  return sort @found;
}

=head2 stash_for( $relative_path )

Template variables for one template. Almost every template renders correctly
against an empty stash: Template Toolkit is not in STRICT mode, so undefined
variables become the empty string and the markup structure still appears in
full, which is what a snapshot needs to capture.

The single exception is a CSV template whose first statement after loading the
plugin is C<[% CSV.dump(headings) %]>. Template::Plugin::CSV dereferences that
argument as an array, and an undefined C<headings> arrives as the empty string,
which dies under C<strict refs> before any output is produced. The key is
C<headings>, not C<results>: the C<FOREACH> over C<results> further down is
harmless against an empty stash, because Template Toolkit iterates an undefined
value as an empty list. Verified 2026-08-02 against all three stashes.

Two further templates carry Bootstrap or Font Awesome classes that an empty
stash never reaches, because the class-bearing markup sits behind a truthy
condition:

=over

=item C<sidebar/report/generic_report.tt>

The class-bearing branch only runs when C<report.rconfig.bind_params.size> is
true, so the stash needs one bind param entry to take that branch at all.

=item C<ajax/admintask/orphaned.tt>

The whole accordion is wrapped in C<[% IF orphans.size E<gt> 0 %]>, so the
stash needs one orphan row, even an empty one, to get past the guard.

=back

Two other templates also carry classes and are still left on an empty stash.
Both are recorded here as known blind spots rather than driven with fixtures:

=over

=item C<ajax/device/ports_csv.tt>

Emits CSV, not HTML: C<grep> finds zero C<class="..."> attributes anywhere in
its source. No stash, however elaborate, would give a snapshot of this
template anything to guard against a markup regression.

=item C<externallinks.tt>

The entire file is five C<BLOCK> definitions (C<external_link>,
C<external_mac_links>, C<external_ip_links>, C<external_device_links>,
C<external_device_port_links>) and no top-level C<PROCESS> or C<INCLUDE> of
any of them. Each block is only ever reached from another template that names
it explicitly. Verified empirically: even a fully populated stash supplying
C<settings.external_links.node> and C<item.net_mac.as_ieee> still produces the
same handful of blank lines as an empty stash, because rendering the file on
its own never executes a directive that calls into any block. No stash can
fix this; only rendering it from a caller that names a block would.

=back

=cut

sub stash_for {
  my $view = shift;

  return { headings => [] }
    if $view eq 'ajax/report/generic_report_csv.tt';

  return { report => { rconfig => { bind_params =>
             [ { param => 'q', type => 'text', default => '' } ] } } }
    if $view eq 'sidebar/report/generic_report.tt';

  return { orphans => [ {} ] }
    if $view eq 'ajax/admintask/orphaned.tt';

  return {};
}

=head2 render_template( $relative_path )

Returns C<($html, undef)> on success or C<(undef, $error)> on failure.

=cut

sub render_template {
  my $view = shift;
  my $engine = _engine();
  my $out = '';
  # Templates read empty values from the stash; that is expected here and the
  # resulting numeric warnings are noise, not signal.
  local $SIG{__WARN__} = sub { };
  if ($engine->process($view, stash_for($view), \$out)) {
    return ($out, undef);
  }
  return (undef, scalar $engine->error);
}

=head2 snapshot_path( $relative_path )

Where the committed snapshot for a template lives.

=cut

sub snapshot_path {
  my $view = shift;
  return join '/', SNAPSHOT_ROOT, $view . '.html';
}

1;
