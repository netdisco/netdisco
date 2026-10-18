package App::Netdisco::Util::Configuration;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use Hash::Merge::Simple;
use MIME::Base64 'decode_base64';
use Storable 'dclone';
use Try::Tiny;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  effective_setting
  forget_effective_config
  refresh_managed_acl
  parse_params_to_config
  split_params_to_config
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 refresh_acl_from_database( $name )

Given an AccessControlListName result with prefetched C<mappings>, creates
the corresponding C<hosts_groups> ACL in configuration.

=cut

sub refresh_managed_acl {
    my $name = shift;

    # the group is rebuilt on every refresh: this runs on every API request in
    # a long-lived web worker, and adding to the last refresh's group kept rows
    # deleted in the ACL editor in force, and grew the group each time. an ACL
    # with no rows leaves no group, which refuses, as an empty list would not.
    delete config->{'host_groups'}->{$name->acl_name};

    foreach my $map (sort {$a->id <=> $b->id} $name->mappings->all) {
        # take every left and optionally right acl (if host_host or host_port) and
        # synthesize them into little host groups
        foreach my $acl ($map->left_acl, $map->right_acl) {
            my $group = 'synthesized_group_'. $acl->id;
            config->{'host_groups'}->{$group} = $acl->rules;
            last if $name->acl_type eq 'host';
        }

        # store in host groups with acl name
        # make a top level group which is list of group: refs (if host)
        if ($name->acl_type eq 'host') {
            push @{ config->{'host_groups'}->{$name->acl_name} },
              ('group:synthesized_group_'. $map->left_acl->id);
        }
        # OR hash of group: to group: refs (if host_host or host_port)
        else {
            config->{'host_groups'}->{$name->acl_name}
              ->{'group:synthesized_group_'. $map->left_acl->id}
              = ('group:synthesized_group_'. $map->right_acl->id);
        }
    }
}

=head1 effective_setting( $name )

Returns setting C<$name> as Netdisco will use it: the YAML configuration with
ACLs from the ACL Manager laid over it. For now that changes
C<portctl_by_role>, which gains the C<host_port> ACLs, and C<host_groups>,
which gains the C<synthesized_group_*> groups those roles name. Any other
setting comes back unchanged.

The overlay is built on first use and kept in C<vars>, so the database is read
at most once per web request (Dancer clears C<vars> for each one) or backend
job (C<Worker::Runner> calls C<forget_effective_config>).

=cut

sub effective_setting {
    my $name = shift;
    my $overlay = vars->{'effective_config'}
      ||= _build_overlay( _load_managed_acls() );
    return (exists $overlay->{$name} ? $overlay->{$name} : setting($name));
}

=head1 forget_effective_config

Drops the cached overlay, so the next C<effective_setting> reads the database
again. Call it after changing ACLs or C<portctl_by_role> within one request
or job.

=cut

sub forget_effective_config { delete vars->{'effective_config'}; return }

# the one database read behind effective_setting, and the edge tests replace
sub _load_managed_acls {
    {
        # with no deployed schema (tests, a fresh install) there is nothing to load
        local $SIG{__WARN__} = sub {
            my $warning = shift;
            return if $warning =~ /Your DB is currently unversioned/;
            warn $warning;
        };
        return () unless schema(vars->{'tenant'})->get_db_version;
    }

    return schema(vars->{'tenant'})->resultset('AccessControlListName')->search(
      { 'me.acl_type' => 'host_port' },
      { prefetch => { mappings => [qw/left_acl right_acl/] },
        order_by => [qw/me.acl_name mappings.id/] },
    )->all;
}

# the shape sync_portctl_roles gave a database role, without writing to config:
# a hash of each row's device side, as a synthesized group, to its port rules
# as stored. the tenant is in the group name because the token ACL code
# synthesizes groups by ACL id alone, from the default tenant's database.
sub _build_overlay {
    my @names  = @_;
    my $tenant = vars->{'tenant'} || 'netdisco';
    my $yaml   = setting('portctl_by_role') || {};

    my %roles  = map {( $_ => ($yaml->{$_} || '!group:__ANY__') )} keys %$yaml;
    my %groups = ();

    foreach my $name (@names) {
        my %role = ();
        foreach my $map (sort {$a->id <=> $b->id} $name->mappings->all) {
            my $left = $map->left_acl or next;
            my $group = sprintf 'synthesized_group_%s_%s', $tenant, $left->id;
            $groups{$group} = $left->rules;
            $role{"group:$group"} = ($map->right_acl ? $map->right_acl->rules : undef);
        }
        $roles{ $name->acl_name } = \%role;
    }

    return {
      portctl_by_role => \%roles,
      ((scalar keys %groups)
        ? (host_groups => { %{ setting('host_groups') || {} }, %groups }) : ()),
    };
}

=head1 CONFIGURATION OVERRIDE

Users can override or add to Netdisco configuration from the command line,
or in a job specification in a configured schedule or API-submitted job.
This in turn overrides the NETDISCO_WITH_CONFIGURATION environment variable.

Configuration is provided to a Job in either the C<port> or C<subaction>
(C<extra>) slots. There is a way to provide configuration when these
slots are also used for job parameters.

Configuration can be provided directly as JSON, as simple "k1=v1,k2=v2"
format, or, when job parameters are needed, in a JSON dictionary slot
"C<with>" alongside the job parameter in a dictionary slot "C<value>".

When configuration override is provided to BOTH the C<port> and C<subaction>
(C<extra>) slots the BEHAVIOUR IS UNDEFINED. Best to avoid doing that.

Note that earlier behaviour of providing a bare string as a C<device_auth>
tag hint is now unsupported and C<device_auth_tag_hint> setting can be
used instead.

Also note that this implementation precludes providing a dictionary as
the "extra" configuration to any action (as it will be interpreted and
consumed as configuration setting overrides). Lists and strings remain
supported.

For example:

=over 4

=item * C<undef> (changed to empty string if subaction)

=item * C<unchanged>

=item * C<"unchanged">

=item * C<'"unchanged"'>

=item * C<[{"mac": "string", "port": "string"}]>

=item * C<{"mac": "string", "port": "string"}> (unsupported)

=item * C<{"value": [{"mac": "string", "port": "string"}]}>

=item * C<{"value": {"mac": "string", "port": "string"}}>

=item * C<{"value": '{"mac": "string", "port": "string"}'}>

=item * C<{"value": "unchanged", "with": {"snmptimeout": 5000000}}>

=item * C<{"value": "unchanged", "with": '{"snmptimeout": 5000000}'}>

=item * C<{"value": "unchanged", "with": 'snmptimeout=5000000'}>

=item * C<{"snmptimeout": 5000000}>

=item * C<'{"snmptimeout": 5000000}'>

=item * C<snmptimeout=5000000>

=item * C<{"value": "unchanged", "with": "FAILS"}> (unsupported)

=item * C<{"value": "unchanged", "with": ["FAILS"]}> (unsupported)

=back

=head1 parse_params_to_config

Takes a defined value, works out what has been provided. If there is
configuration to override it applies that. If there is a residual value
to return, it returns that, otherwise returns undef.

=cut

sub parse_params_to_config {
  my ($actual_value, $overrides) = split_params_to_config(shift);
  merge_into_configuration($overrides) if $overrides;
  return $actual_value;
}

=head1 split_params_to_config

Works out what has been provided as C<parse_params_to_config> does, but
applies nothing. Returns the residual value and a hashref of the
configuration overrides, or undef when there are none.

=cut

sub split_params_to_config {
  my $orig_value = shift;
  return (undef, undef) unless defined $orig_value;

  # value via "schedule:" deployment.yml would already be a Perl struct
  my $struct = (ref $orig_value ne q{})
    ? $orig_value
    : try { from_json($orig_value) };
    # reminder: from_json of a "" string returns the string, but unquoted throws error
    # so struct could still be a string, or struct reference, or undef on parse error
  my $came_from_json = (((defined $struct)
    and (ref $orig_value eq q{}) and ($struct ne $orig_value)) ? true : false);

  # case when value is a struct but not config (hashref), just leave it alone
  if ((ref $struct ne q{}) and (ref $struct ne ref {})) {
      return ($orig_value, undef);
  }

  # case when value is an empty string
  if (($orig_value eq q{}) or (defined $struct and $struct eq q{})) {
      return (q{}, undef);
  }

  # finally, we have either a lengthy string or a struct
  my $value = ((defined $struct)
    ? $struct
    : $orig_value);

  # if a lengthy string, it could be k=v config
  if (ref $value eq q{}) {
      if ($value =~ m/^(?:(?:[^=,]+)=(?:[^=,]+))(?:,(?:[^=,]+)=(?:[^=,]+))*$/) {
          $value = parse_config_string_to_dict($value);

      }
      else {
          # try to decode base64
          my $decoded = try { from_json(decode_base64($value)) }; # might explode
          if (defined $decoded and ref {} eq ref $decoded) {
              return split_params_to_config($decoded);
          }
          # some other use of subaction (file ref, log comment, etc)
          else {
              return ($value, undef);
          }
      }
  }

  # now value is a hashref, look for with/value setup
  my $actual_value = undef;

  if (exists $value->{value}) {
      # if JSON was thawed from the value, refreeze it
      my $inner = delete $value->{value};
      $actual_value = (((ref $inner ne q{}) and $came_from_json)
        ? to_json($inner) : $inner);
  }

  $value = $value->{'with'} if exists $value->{'with'};
  # we can recurse to decode a stringified JSON 'with'
  my $overrides = ((ref $value eq ref {})
    ? $value : (split_params_to_config($value))[1]);

  return ($actual_value,
    ((ref $overrides eq ref {} and scalar keys %$overrides) ? $overrides : undef));
}

sub parse_config_string_to_dict {
  my $extra = shift;
  return {} unless
    $extra and (ref $extra eq q{}) and $extra =~ m/=/;

  # must be key1=val1,key2=val2
  my $dict = {};
  my @kvs = split m/,/, $extra;
  foreach my $kv (@kvs) {
      next unless $kv;
      die "bad syntax for subaction, missing =\n" unless $kv =~ m/=/;
      my ($k, $v) = split m/=/, $kv, 2;
      $dict->{$k} = $v;
  }

  return $dict;
}

sub merge_into_configuration {
    my $newconfig = shift;
    die "bad configuration format\n" unless ref $newconfig eq ref {};
    my $SETTINGS = config();
    $SETTINGS = Hash::Merge::Simple::merge( $SETTINGS, $newconfig );
    set($_ => $SETTINGS->{$_}) for keys %$newconfig;
}

true;