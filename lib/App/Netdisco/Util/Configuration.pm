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
  refresh_managed_acl
  load_acls_from_database
  parse_params_to_config
  split_params_to_config
  snmp_charset_maps
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

=head1 load_acls_from_database

Loads all the managed ACLs into C<host_groups>.

=cut

sub load_acls_from_database {
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

    my @names = schema(vars->{'tenant'})->resultset('AccessControlListName')
      ->search(undef, { prefetch => { mappings => [qw/left_acl right_acl/] } })->all;

    # for each named acl
    refresh_managed_acl($_) for @names;
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

=head1 snmp_charset_maps( $raw )

Returns the C<snmp_charset> setting as a list of maps from ACL to a list of
charset names, from any of the forms it may be written in: a charset name, a
map whose values are a name or a list, or a list of those maps. Undef,
references and empty names are dropped. Returns C<< [ { 'group:__ANY__' => [] } ] >>
when nothing is left.

=cut

sub snmp_charset_maps {
  my $raw = shift;
  my @maps = (ref [] eq ref $raw) ? @$raw : ($raw);
  my @normalized;

  foreach my $map (@maps) {
    $map = { 'group:__ANY__' => $map } if defined $map and q{} eq ref $map;
    next unless ref {} eq ref $map;
    push @normalized, { map { ($_ => _charset_list($map->{$_})) } keys %$map };
  }

  return scalar @normalized ? \@normalized : [ { 'group:__ANY__' => [] } ];
}

sub _charset_list {
  my ($value) = @_;
  my @names = (ref [] eq ref $value) ? @$value : ($value);
  return [ grep { defined and q{} eq ref $_ and length } @names ];
}

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
  # 1769 fix json number parsing ignoring trailing zeroes (ex: 2.10 -> 2.1)
  my $value = ((defined $struct)
    ? ((ref $struct eq q{} and $orig_value !~ m/^\s*"/) ? $orig_value : $struct)
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
