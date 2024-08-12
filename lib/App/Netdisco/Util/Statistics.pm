package App::Netdisco::Util::Statistics;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use Time::Piece; # for OO localtime

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/pretty_version update_stats/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Statistics

=head1 DESCRIPTION

Update the Netdisco statistics.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 update_stats()

Update the Netdisco statistics, either new for today or updating today's
figures.

=cut

sub update_stats {
  my $schema = schema(vars->{'tenant'});
  eval { require SNMP::Info };
  my $snmpinfo_ver = ($@ ? 'n/a' : $SNMP::Info::VERSION);
  my $postgres_ver = pretty_version($schema->storage->dbh->{pg_server_version}, 2);

  # roll everything back if we're testing
  my $txn_guard = $ENV{ND2_DB_ROLLBACK}
    ? $schema->storage->txn_scope_guard : undef;

  # TODO: (when we have the capabilities table?)
  #  $stats{waps} = sql_scalar('device',['COUNT(*)'], {"model"=>"AIR%"});

  $schema->txn_do(sub {
    $schema->resultset('Statistics')->update_or_create({
      day => localtime->ymd,

      device_count =>
        $schema->resultset('Device')->count_rs->as_query,
      device_ip_count =>
        $schema->resultset('DeviceIp')->count_rs->as_query,
      device_link_count =>
        ( $postgres_ver =~ m/^8\./ ? 0 :
        $schema->resultset('Virtual::DeviceLinks')->search(undef, {
            select => [ { coalesce => [ { sum => 'aggports' }, 0 ] } ],
            as => ['totlinks'],
        })->get_column('totlinks')->as_query ),
      device_port_count =>
        $schema->resultset('DevicePort')->count_rs->as_query,
      device_port_up_count =>
        $schema->resultset('DevicePort')->count_rs({up => 'up'})->as_query,
      ip_table_count =>
        $schema->resultset('NodeIp')->count_rs->as_query,
      ip_active_count =>
        $schema->resultset('NodeIp')->search({-bool => 'active'},
          {columns => 'ip', distinct => 1})->count_rs->as_query,
      node_table_count =>
        $schema->resultset('Node')->count_rs->as_query,
      node_active_count =>
        $schema->resultset('Node')->search({-bool => 'active'},
          {columns => 'mac', distinct => 1})->count_rs->as_query,

      netdisco_ver => pretty_version($App::Netdisco::VERSION, 3),
      snmpinfo_ver => pretty_version($snmpinfo_ver, 3),
      schema_ver   => $schema->schema_version,
      perl_ver     => pretty_version($], 3),
      python_ver   => vars->{'python_ver'},
      pg_ver       => $postgres_ver,

    }, { key => 'primary' });
  });
}

=head2 pretty_version ( $versionstring , $seglen )

Splits a string (only numbers and dots allowed) into a number of parts which
are seglen long, then removes all leading zeros from each part and returns
the parts joined by dots as one string.

Returns the original versionstring if unallowed characters are found or seglen
is negative.

Returns C<undef> if seglen is zero.

=cut

sub pretty_version {
  my ($version, $seglen) = @_;
  return unless $version and $seglen;
  return $version unless $seglen > 0;
  return $version if $version !~ m/^[0-9.]+$/;
  $version =~ s/\.//g;
  $version = (join '.', reverse map {scalar reverse}
    unpack("(A${seglen})*", reverse $version));
  $version =~ s/\.000/.0/g;
  $version =~ s/\.0+([1-9]+)/.$1/g;
  return $version;
}

true;
