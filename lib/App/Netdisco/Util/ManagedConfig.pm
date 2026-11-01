package App::Netdisco::Util::ManagedConfig;

use strict;
use warnings;

# config processing must be finished before the YAML copy is taken
use App::Netdisco::Configuration ();

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use Storable 'dclone';
use Try::Tiny;

use base 'Exporter';
our @EXPORT_OK = qw/
  tenant_key
  acl_txn_do
  load_managed_config
  refresh_managed_config
  apply_managed_config
  capture_yaml_settings
  yaml_setting
  _read_config_version
  _bump_config_version
  _read_acl_rows
  _build_overlay
/;

# kept here and not in CONFIG, so that dumpconfig and setting() only ever see
# what the code actually uses. declared with our so that tests can reset them.
our %YAML;      # setting name => clean copy of its YAML value
our $CAPTURED;  # true once %YAML has been taken in this process
our %CACHE;     # tenant key => { version => Int, overlay => HashRef }
our $LOADED;    # true once any overlay has been built in this process

=head1 NAME

App::Netdisco::Util::ManagedConfig - ACL Manager data loaded into the config

=head1 DESCRIPTION

The C<config_version> table holds one counter per scope. The C<acl> counter
goes up by one every time the ACL Manager writes, so a process can tell
whether its copy is stale with one cheap read.

The counter is bumped in Perl by L</acl_txn_do>, not by a database trigger.
That keeps the bump visible at the place where the ACL is written, and a
reader of the writing code can see which writes are counted.

Because only those writes are counted, two kinds of change go unnoticed: an
ACL table edited by hand, for example in C<psql>, and a restored database dump
whose counter equals the one a process last saw. After either, restart
C<netdisco-web> and C<netdisco-backend>, or bump the counter by hand:

  UPDATE config_version SET version = version + 1 WHERE scope = 'acl';

=head1 EXPORT_OK

=head2 tenant_key

Returns the current tenant, or C<netdisco> for the default tenant.

=cut

sub tenant_key { return (vars->{'tenant'} || 'netdisco') }

=head2 acl_txn_do( $coderef )

Runs C<$coderef> in a transaction on the current tenant's database, then bumps
the C<acl> counter in that same transaction and returns what C<$coderef>
returned. If C<$coderef> dies nothing is bumped and the error propagates.

=cut

sub acl_txn_do {
  my $code = shift;
  my $schema = schema(tenant_key());
  return $schema->txn_do(sub {
    my @ret = wantarray ? $code->() : scalar $code->();
    _bump_config_version($schema);
    return wantarray ? @ret : $ret[0];
  });
}

# Plain DBI rather than a resultset: this read happens on every request, and
# DBIC costs about 1 ms against 0.03 ms. Dies if the table or row is missing
# (database not yet upgraded); the caller decides what that means.
sub _read_config_version {
  my $tenant_key = shift;
  return schema($tenant_key)->storage->dbh_do(sub {
    my ($storage, $dbh, @bind) = @_;
    my ($version) = $dbh->selectrow_array(
      'SELECT version FROM config_version WHERE scope = ?', undef, @bind);
    return $version;
  }, 'acl');
}

sub _bump_config_version {
  my $schema = shift;
  $schema->storage->dbh_do(sub {
    my ($storage, $dbh, @bind) = @_;
    $dbh->do('UPDATE config_version SET version = version + 1 WHERE scope = ?',
      undef, @bind);
  }, 'acl');
  return;
}

=head2 load_managed_config

Brings the current tenant's ACL Manager roles and named groups into
C<portctl_by_role> and C<host_groups>, reading the ACL tables only if the
counter moved since the last load. The first call in a process takes the clean
YAML copy (see L</capture_yaml_settings>).

A failed database read never makes it die. It can die only while taking the
YAML copy, if one of the two settings is a hash holding something
L<Storable> can't copy, such as a code reference, which YAML can't express.
A value of either setting that isn't a hash at all counts as empty.

=cut

sub load_managed_config {
  capture_yaml_settings() unless $CAPTURED;
  my $tenant_key = tenant_key();
  refresh_managed_config($tenant_key);
  apply_managed_config($tenant_key);
  return;
}

=head2 refresh_managed_config( $tenant_key )

Reads the tenant's counter and, if it moved, rebuilds the tenant's overlay from
its ACL rows. A failed read drops the tenant's cache entry.

=cut

sub refresh_managed_config {
  my $tenant_key = shift;

  # a failed read (no database, or no config_version row because the schema
  # is not upgraded yet) counts as an empty ACL Manager, the way get_user_roles
  # in Web/Auth/Provider/DBIC.pm returns no roles when its query fails. the
  # failure is not cached, so the next call tries again.
  try {
    # the counter is read before the rows: a write that commits between the
    # two reads then leaves new rows stored under the old counter, which only
    # costs one more reload. reading the rows first could store old rows under
    # the new counter, and they would never be reloaded.
    my $version = _read_config_version($tenant_key);
    die "no acl row in config_version\n" unless defined $version;

    return if exists $CACHE{$tenant_key}
      and $CACHE{$tenant_key}->{version} == $version;

    $CACHE{$tenant_key} = {
      version => $version,
      overlay => _build_overlay($tenant_key, _read_acl_rows($tenant_key)),
    };
    $LOADED = 1;
  }
  catch {
    delete $CACHE{$tenant_key};
  };

  return;
}

=head2 apply_managed_config( $tenant_key )

Writes the clean YAML copy merged with the tenant's overlay into
C<portctl_by_role> and C<host_groups>. ACL Manager entries replace YAML ones of
the same name.

=cut

sub apply_managed_config {
  my $tenant_key = shift;

  # until something has been loaded in this process CONFIG is left exactly as
  # it is, so tests with no database keep the values they set, as they keep
  # their roles when get_user_roles fails. once something was loaded, a failed
  # read must put the YAML back, or a worker would keep stale database roles,
  # or those of the last request's tenant.
  return unless exists $CACHE{$tenant_key} or $LOADED;

  my $overlay = exists $CACHE{$tenant_key}
    ? $CACHE{$tenant_key}->{overlay}
    : { portctl_by_role => {}, host_groups => {} };

  # new top-level hashes every time, so a job's override merged into the last
  # apply never carries into the next one
  my $yaml_roles = $YAML{'portctl_by_role'} || {};
  config->{'portctl_by_role'} = {
    (map { ($_ => ($yaml_roles->{$_} || '!group:__ANY__')) } keys %$yaml_roles),
    %{ $overlay->{'portctl_by_role'} },
  };
  config->{'host_groups'} = {
    %{ $YAML{'host_groups'} || {} },
    %{ $overlay->{'host_groups'} },
  };

  return;
}

=head2 capture_yaml_settings

Takes the clean copy of the YAML values that the ACL Manager adds to, replacing
any copy taken before. A value that isn't a hash is taken as an empty hash.

L</load_managed_config> and L</yaml_setting> call this themselves the first
time either runs in a process, so nothing else needs to. Tests call it again
after setting new YAML values.

The copy is taken then, and not as this module loads, for three reasons:

=over 4

=item *

In production the first request or job always runs before anything changes
these settings, so the copy is the same either way.

=item *

C<Web.pm> loads site web plugins after C<App::Netdisco::Web::ManagedConfig>,
which loads this module. A plugin that adds to C<host_groups> as it loads is
still in the copy.

=item *

A value a test sets before its first request or job counts as YAML. A copy
taken as the module loaded missed it, and once a database answered, even with
an empty ACL Manager, the next load rebuilt the setting from that copy and the
test's value was gone.

=back

=cut

sub capture_yaml_settings {
  foreach my $name (qw/portctl_by_role host_groups/) {
    my $value = setting($name);
    # every request and job applies this copy, so a mistyped value such as
    # portctl_by_role: [] must not make all of them die, discovery included
    $YAML{$name} = ((ref $value eq 'HASH') ? dclone($value) : {});
  }
  $CAPTURED = 1;
  return;
}

=head2 yaml_setting( $name )

Returns the clean YAML copy of C<portctl_by_role> or C<host_groups>, without
anything from the ACL Manager. Takes the copy first if this process hasn't yet.

=cut

sub yaml_setting {
  capture_yaml_settings() unless $CAPTURED;
  return $YAML{ $_[0] };
}

# host_host ACLs are not read: nothing uses them as config
sub _read_acl_rows {
  my $tenant_key = shift;
  return schema($tenant_key)->resultset('AccessControlListName')->search(
    { 'me.acl_type' => [qw/host host_port/] },
    { prefetch => { mappings => [qw/left_acl right_acl/] },
      order_by => [qw/me.acl_name mappings.id/] },
  )->all;
}

# synthesized group names carry the tenant because ACL ids from different
# tenant databases can clash
sub _build_overlay {
  my ($tenant_key, @rows) = @_;
  my (%roles, %groups);

  foreach my $name (@rows) {
    my $is_role = ($name->acl_type eq 'host_port');

    # an ACL with no rows still replaces a YAML entry of the same name, and
    # matches nothing
    if ($is_role) { $roles{ $name->acl_name } = {} }
    else          { $groups{ $name->acl_name } = [] }

    foreach my $map ($name->mappings->all) {
      my $left  = $map->left_acl;
      my $group = sprintf('synthesized_group_%s_%s', $tenant_key, $left->id);
      $groups{$group} = $left->rules;

      if ($is_role) {
        my $right = $map->right_acl;
        $roles{ $name->acl_name }->{"group:$group"} = ($right ? $right->rules : undef);
      }
      else {
        push @{ $groups{ $name->acl_name } }, "group:$group";
      }
    }
  }

  return { portctl_by_role => \%roles, host_groups => \%groups };
}

1;
