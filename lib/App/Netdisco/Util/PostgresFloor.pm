package App::Netdisco::Util::PostgresFloor;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';
use Try::Tiny;

use App::Netdisco::Util::Statistics 'postgres_version';

use base 'Exporter';
our @EXPORT_OK = qw/
  $POSTGRES_FLOOR_MAJOR
  postgres_floor_warning
  warn_postgres_floor_all_tenants
/;

our $POSTGRES_FLOOR_MAJOR = 14;

=head1 NAME

App::Netdisco::Util::PostgresFloor - Warn when PostgreSQL is older than a future release will accept

=head2 postgres_floor_warning( $server_version_num, $label )

Returns warning text for a server older than C<$POSTGRES_FLOOR_MAJOR>, naming
the database C<$label>. Returns C<undef> for a supported or unreadable version.

=head2 warn_postgres_floor_all_tenants( $log_coderef, \%override )

Calls C<$log_coderef> with a warning for the main database and for each
configured tenant database that is below the floor. A database that cannot be
reached is skipped silently. C<%override> (C<labels>, C<version_for>) replaces
the configured databases, for tests.

=cut

sub postgres_floor_warning {
  my ($server_version_num, $label) = @_;
  my $display = postgres_version($server_version_num) or return undef;
  return undef if $server_version_num < 90000;
  return undef if int($server_version_num / 10000) >= $POSTGRES_FLOOR_MAJOR;

  return sprintf 'PostgreSQL %s for database "%s" is older than %d. '
    . 'A future release of Netdisco will require PostgreSQL %d or later. '
    . 'See https://github.com/netdisco/netdisco/wiki/Release-Notes',
    $display, $label, $POSTGRES_FLOOR_MAJOR, $POSTGRES_FLOOR_MAJOR;
}

sub warn_postgres_floor_all_tenants {
  my ($log, $override) = @_;
  my @labels = $override ? @{ $override->{labels} }
    : ('netdisco', map { $_->{tag} } grep { $_->{tag} and $_->{tag} ne 'netdisco' }
        @{ setting('tenant_databases') || [] });
  my $version_for = $override ? $override->{version_for} : \&_live_version;

  foreach my $label (@labels) {
    my $server_version_num = try { $version_for->($label) } catch { undef };
    my $text = postgres_floor_warning($server_version_num, $label) or next;
    $log->($text);
  }
}

sub _live_version {
  my $label = shift;
  # a tenant host that drops packets must not stall boot for the TCP timeout
  local $ENV{PGCONNECT_TIMEOUT} = $ENV{PGCONNECT_TIMEOUT} || 3;
  my $storage = schema($label)->storage;
  my $version = $storage->dbh->{pg_server_version};
  # the web master forks workers, which must not inherit this connection
  $storage->disconnect;
  return $version;
}

true;
