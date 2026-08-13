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

Seven further templates carry Bootstrap or Font Awesome classes behind a
C<FOREACH> over a result set, and were measured (2026-08-04) to render fewer
than half of their migration-relevant class tokens against an empty stash.
Each gets the smallest result set that reaches every branch of interest. Four
of the seven also gate some of that markup on C<user_has_role(...)>, a Perl
function rather than a stash value; each of those four stubs it the same way,
as a coderef returning true, rather than leaving some templates faked and
others not:

=over

=item C<ajax/device/ports.tt>

One row per icon state (admin-down, STP-blocking, error-disabled, free,
link-down, subinterface-fold) plus VLAN and PoE data, so every branch of the
per-port status icon and VLAN-count logic renders at least once, plus
C<user_has_role> stubbed true to reach the port-log modal. C<results> rows are
plain hashrefs; C<row.get_column> and C<row.has_column_loaded> are
DBIx::Class::Row methods this harness does not model, so one row supplies
C<has_column_loaded> as a coderef to reach the "port is free" branch, and the
neighbour-discovery icons that depend on C<get_column> are left as a gap.
C<nodes>, C<ips> and C<mac_format_call> are, as in production, the names of
the row accessors the template should call, not the data itself.

=item C<layouts/main.tt>

A logged-in session reaches the search bar, the account menu, and (with a
tenant configured) the tenant-switcher dropdown; C<user_has_role> stubbed true
reaches the Admin dropdown's static buttons. The three menus built from
registered plugins each get the smallest set that reaches every branch of the
loop that draws them: one navbar item, marked current so the Reports and Admin
toggles supply the inactive form of the same construct; the stock eight report
categories with two of them populated, so the empty-category branch renders
too, and one of the three reports hidden, as C<portlog> is in production; and
an admin list holding a task, a divider and a second task. Tags and labels are
the ones the shipped plugins register, so a reader can find each one in
C<lib/App/Netdisco/Web/Plugin/>.

=item C<ajax/device/details.tt>

A single device row, plus C<user_has_role> stubbed true because most of this
template's buttons and its snapshot dropdown are gated on the admin role and
there is no cheaper way to reach them.

=item C<ajax/admintask/jobqueue.tt>

One queued job. An empty C<results> takes the "queue is empty" branch and
never reaches the table at all.

=item C<ajax/admintask/acleditor.tt>

C<results> here is a DBIx::Class::ResultSet in production, walked with
C<results.next> rather than C<FOREACH>. The stash supplies the same interface
as a hashref holding one C<next> coderef that returns a single rule pair then
undef.

=item C<ajax/admintask/aclmanager.tt>

One ACL row, which is all its C<FOREACH> needs: every button and icon in the
row is unconditional once the row exists.

=item C<index.tt>

Takes the same logged-in-session branch as C<layouts/main.tt>, plus one flag
(C<vars.notfound>) for the "page not found" banner, plus C<user_has_role>
stubbed true to reach the Admin discovery form. The guest/login banners are a
remaining gap: they render only when C<NOT session.logged_in_user>, which is
mutually exclusive with the logged-in branch that unlocks everything else in
this template.

=back

B<A harness-wide note, not specific to any one template above:>
C<Template::Stash> hides any key with a leading underscore from templates
unless a caller turns that check off. C<lib/App/Netdisco/Web.pm> turns it off
before every render and C<render_template> below does the same, so a fixture
here drives C<settings._navbar_items>, C<settings._admin_tasks>,
C<settings._admin_order>, C<settings._reports>, C<settings._reports_menu>,
C<settings._report_order>, C<settings._extra_device_details>,
C<settings._extra_device_port_cols>, C<settings._additional_javascript> and
C<settings._additional_css> exactly as production does. Where markup behind one
of those is missing from a snapshot it is because no fixture supplies the
value, never because the path cannot be reached.

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

  if ($view eq 'ajax/device/ports.tt') {
    return {
      # stubbed true to reach the port-log modal, which is otherwise the
      # only gate in this template that depends on a Perl function rather
      # than a data structure
      user_has_role => sub { 1 },
      params => {
        c_admin => 1, c_port => 1, c_name => 1, c_pvid => 1, c_tags => 1,
        c_power => 1, c_vmember => 1, c_nodes => 1, c_neighbors => 1,
        p_fold_dotzero => 1,
      },
      settings => {
        portctl_topology => 1,
        devport_vlan_limit => 10,
        devport_vlans_collapse_threshold => 2,
      },
      # production passes the row accessor names here, not the data itself
      nodes => 'client_nodes',
      ips => 'client_ips',
      mac_format_call => 'as_string',
      vlans => {
        'Gi1/1' => { vlan_count => 1 },
        'Gi1/3' => { vlan_count => 1 },
        'Gi1/6' => { vlan_count => 99 },
        'Gi1/9' => { vlan_count => 3, vlan_set => [ 10, 20 ] },
      },
      results => [
        # up port carrying a tag, a LAG membership, and admin-edit permission
        { port => 'Gi1/1', up_admin => 'up', up => 'up', stp => 'forwarding',
          slave_of => 1, port_acl_service => 1, port_acl_name => 1,
          port_acl_pvid => 1, filtered_tags => ['core'],
          client_nodes => [ { active => 0,
            net_mac => { as_string => 'aa:bb:cc:00:01:01' } } ] },
        # administratively disabled port
        { port => 'Gi1/2', up_admin => 'down', port_acl_service => 1 },
        # up port with a spanning-tree block and few enough VLANs to name them
        { port => 'Gi1/3', up_admin => 'up', up => 'up', stp => 'blocking' },
        # error-disabled port, also on the non-dot-zero subinterface fold
        { port => 'Gi1/4', up_admin => 'up', up => 'down',
          error_disable_cause => 'err-disable', has_subinterface_group => 1,
          has_only_dot_zero_subinterface => 0 },
        # link-down port marked free by has_column_loaded/is_free
        { port => 'Gi1/5', up_admin => 'up', up => 'down',
          has_column_loaded => sub { 1 }, is_free => 1 },
        # link-down port with too many VLANs to list individually
        { port => 'Gi1/6', up_admin => 'up', up => 'down' },
        # up port with PoE and enough VLANs to need the "show more" toggle
        { port => 'Gi1/9', up_admin => 'up', up => 'up',
          power => { admin => 'true', power => 5 } },
        # up port whose only subinterface is the dot-zero one
        { port => 'Gi1/10', up_admin => 'up', up => 'up',
          has_subinterface_group => 1, has_only_dot_zero_subinterface => 1 },
      ],
    };
  }

  if ($view eq 'layouts/main.tt') {
    return {
      session => { logged_in_user => 'demo' },
      # stubbed true to reach the Admin dropdown's static buttons
      user_has_role => sub { 1 },
      # marks the one navbar item current, so the two dropdown toggles below
      # supply the same construct in its inactive form
      vars => { nav => 'inventory' },
      settings => {
        tenant_databases => ['netdisco'],
        tenant_data => { netdisco => { displayname => 'Netdisco' } },
        tenant_tags => ['netdisco'],
        _navbar_items => [
          { tag => 'inventory', path => '/inventory', label => 'Inventory' },
        ],
        # the stock category list, of which two are given reports: the rest
        # take the empty-category branch of the same loop
        _report_order =>
          [qw/Device Port IP Node VLAN Network Wireless/, 'My Reports'],
        _reports_menu => {
          'Device' => ['deviceaddrnodns'],
          'Port'   => ['portssid', 'portlog'],
        },
        _reports => {
          deviceaddrnodns => { label => 'IPs without DNS Entries' },
          portssid        => { label => 'Port SSID Inventory' },
          # registered hidden in production too, which is the case that
          # exercises the menu loop's skip
          portlog         => { label => 'Port Control Log', hidden => 1 },
        },
        _admin_order => [qw/duplicatedevices divider users/],
        # 'divider' is absent from this hash on purpose: register_admin_task
        # pushes the tag onto _admin_order and returns before recording a
        # task, and that asymmetry is what makes the loop's divider branch
        # reachable
        _admin_tasks => {
          duplicatedevices => { label => 'Duplicate Devices' },
          users            => { label => 'User Management' },
        },
      },
    };
  }

  if ($view eq 'ajax/device/details.tt') {
    return {
      # stubbed true because most of this template's actions are admin-only
      user_has_role => sub { 1 },
      d => {
        layers => '01010101', pae_is_enabled => 1,
        is_discoverable => 1, is_arpnipable => 1, is_macsuckable => 0,
      },
      filtered_tags => ['core'],
    };
  }

  if ($view eq 'ajax/admintask/jobqueue.tt') {
    return {
      results => [
        { job => 1, backend => 'localhost', action => 'discover',
          status => 'queued', username => 'demo', duration => '5s' },
      ],
    };
  }

  if ($view eq 'ajax/admintask/acleditor.tt') {
    my @pairs = ( {
      id => 1,
      left_acl_with_dns => { ruleset => [ [ '192.0.2.0/24' ] ] },
      right_acl => { rules => ['80'] },
    } );
    return {
      acl_name => 'demo',
      params => { acl_type => 'host_port' },
      # production's `results` is a DBIx::Class::ResultSet, walked with
      # results.next rather than FOREACH; a coderef reproduces just that
      results => { next => sub { shift @pairs } },
    };
  }

  if ($view eq 'ajax/admintask/aclmanager.tt') {
    return { results => [ { acl_name => 'demo', acl_type => 'host' } ] };
  }

  if ($view eq 'index.tt') {
    return {
      session => { logged_in_user => 'demo' },
      # stubbed true to reach the Admin discovery form
      user_has_role => sub { 1 },
      params => { login_failed => 1 },
      vars => { notfound => 1 },
    };
  }

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
  # Mirrors lib/App/Netdisco/Web.pm:404, which the application sets before
  # every render so settings._foo keys resolve instead of being hidden by
  # Template::Stash's leading-underscore filter. This must run after the
  # _engine() call above: that call is what first loads Template::Stash and
  # assigns its qr/^[_.]/ default, so setting this beforehand would only be
  # overwritten by that load. Localized to this one process() call so the
  # package global cannot leak into another subtest in this process.
  local $Template::Stash::PRIVATE = undef;
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
