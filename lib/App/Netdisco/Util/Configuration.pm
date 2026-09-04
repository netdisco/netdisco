package App::Netdisco::Util::Configuration;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use Hash::Merge::Simple;
use Storable 'dclone';
use Try::Tiny;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  refresh_managed_acl
  load_acls_from_database
  parse_params_to_config
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 refresh_acl_from_database( $name, $where )

Given an AccessControlListName result with prefetched C<mappings>, creates
the corresponding C<$where> ACL in configuration.

=cut

sub refresh_managed_acl {
    my ($name, $where) = @_;
    die "missing correct param to refresh_managed_acl"
        unless (ref $name ne ref q{}) and $where
            and exists setting($where) and (ref {} eq ref setting($where));

    foreach my $map (sort {$a->id <=> $b->id} $name->mappings->all) {
        # take every left and optionally right acl (if host_host or host_port) and
        # synthesize them into little host groups
        foreach my $acl ($map->left_acl, $map->right_acl) {
            my $group = 'synthesized_group_'. $acl->id;
            config->{$where}->{$group} = $acl->rules;
            last if $name->acl_type eq 'host';
        }

        # store in host groups with acl name
        # make a top level group which is list of group: refs (if host)
        if ($name->acl_type eq 'host') {
            push @{ config->{$where}->{$name->acl_name} },
              ('group:synthesized_group_'. $map->left_acl->id);
        }
        # OR hash of group: to group: refs (if host_host or host_port)
        else {
            config->{$where}->{$name->acl_name}
              ->{'group:synthesized_group_'. $map->left_acl->id}
              = ('group:synthesized_group_'. $map->right_acl->id);
        }
    }
}

sub _reload_db_acls_to {
    my $where = shift;
    die "missing correct param to refresh_managed_acl"
        unless $where and exists setting($where) and (ref {} eq ref setting($where));
    my $where_shadow = $where .'_shadow';

    # because this is always called when Netdisco loads, it might happen during tests
    # or other circs when there's no database. exit if so.
    {
        # Temporarily intercept warnings within this block
        local $SIG{__WARN__} = sub {
            my $warning = shift;
            # Silence only the unversioned schema warning
            return if $warning =~ /Your DB is currently unversioned/;
            # Pass all other warnings through
            warn $warning;
        };

        return unless schema(vars->{'tenant'})->get_db_version;
    }

    # reset current config by loading everything from shadow
    config->{$where} = dclone( config->{$where_shadow} || {} );

    my @names = schema(vars->{'tenant'})->resultset('AccessControlListName')
      ->search(undef, { prefetch => { mappings => [qw/left_acl right_acl/] } })->all;

    # for each named acl
    refresh_managed_acl($_, $where) for @names;
}

=head1 load_acls_from_database( @where )

Loads managed ACLs from the database and merges them into the config at
C<@where>. This should only be done lazily and close to the
time of use, to be efficient and also to get the latest ACL settings.

If there exists an entry in C<@where> config from C<deployment.yml>
with the same name as a database role, then the database role overwrites
it. If such a role is removed, then a backup of the original is restored.

=cut

sub load_acls_from_database { _reload_db_acls_to($_) for @_ }

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
  my $orig_value = shift;
  return undef unless defined $orig_value;

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
      return $orig_value;
  }

  # case when value is an empty string
  if (($orig_value eq q{}) or (defined $struct and $struct eq q{})) {
      return q{};
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
          # some other use of subaction (file ref, log comment, etc)
          return $value;
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
  if (ref $value eq ref {}) {
      merge_into_configuration($value);
  }
  else {
      # we can recurse to decode a stringified JSON 'with'
      parse_params_to_config($value);
  }

  return $actual_value;
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