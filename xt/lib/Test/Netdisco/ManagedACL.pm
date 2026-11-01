package Test::Netdisco::ManagedACL;

# Fake ACL Manager rows for tests that can't reach PostgreSQL.
# stub_managed_config replaces the loader's two database reads, the counter
# and the rows, so the overlay build, the merge into CONFIG and every check
# above it still run for real.

use strict;
use warnings;

use App::Netdisco::Util::ManagedConfig ();

use base 'Exporter';
our @EXPORT_OK = qw/stub_managed_config/;

{ package Test::Netdisco::ManagedACL::List;
  sub new   { my ($c, %a) = @_; return bless {%a}, $c }
  sub id    { $_[0]->{id} }
  sub rules { $_[0]->{rules} } }

{ package Test::Netdisco::ManagedACL::Map;
  sub new       { my ($c, %a) = @_; return bless {%a}, $c }
  sub id        { $_[0]->{id} }
  sub left_acl  { $_[0]->{left_acl} }
  sub right_acl { $_[0]->{right_acl} } }

{ package Test::Netdisco::ManagedACL::Maps;
  sub new { my ($c, @rows) = @_; return bless [@rows], $c }
  sub all { @{ $_[0] } } }

{ package Test::Netdisco::ManagedACL::Name;
  sub new      { my ($c, %a) = @_; return bless {%a}, $c }
  sub acl_name { $_[0]->{acl_name} }
  sub acl_type { $_[0]->{acl_type} }
  sub mappings { Test::Netdisco::ManagedACL::Maps->new(@{ $_[0]->{maps} }) } }

# ids are numbered afresh on every read, so a tenant's ids never depend on
# what another tenant holds, as with separate tenant databases
sub _fake_rows {
  my ($acls, $first_id) = @_;
  my $id = $first_id;
  my $map_id = 1;
  my @names;

  foreach my $name (sort keys %{ $acls || {} }) {
    my @maps;
    foreach my $pair (@{ $acls->{$name}->{maps} || [] }) {
      my $left  = Test::Netdisco::ManagedACL::List->new(id => $id++, rules => $pair->[0]);
      my $right = ((scalar @$pair > 1)
        ? Test::Netdisco::ManagedACL::List->new(id => $id++, rules => $pair->[1]) : undef);
      push @maps, Test::Netdisco::ManagedACL::Map->new(
        id => $map_id++, left_acl => $left, right_acl => $right);
    }
    push @names, Test::Netdisco::ManagedACL::Name->new(
      acl_name => $name, acl_type => $acls->{$name}->{type}, maps => \@maps);
  }

  return @names;
}

sub stub_managed_config {
  my %opts = @_;
  my $first_id = $opts{first_id} || 1;
  my $calls = { version_reads => 0, row_reads => 0 };

  {
    no warnings 'redefine';
    *App::Netdisco::Util::ManagedConfig::_read_config_version = sub {
      my $tenant_key = shift;
      $calls->{version_reads}++;
      return (ref $opts{version} eq 'CODE')
        ? $opts{version}->($tenant_key) : $opts{version};
    };
    *App::Netdisco::Util::ManagedConfig::_read_acl_rows = sub {
      my $tenant_key = shift;
      $calls->{row_reads}++;
      my $rows = (ref $opts{rows} eq 'CODE') ? $opts{rows}->() : ($opts{rows} || {});
      return _fake_rows($rows->{$tenant_key}, $first_id);
    };
  }

  # keep_cache changes what the database "holds" without dropping what the
  # loader already built, so a test can show the next load noticing (or not)
  unless ($opts{keep_cache}) {
    %App::Netdisco::Util::ManagedConfig::CACHE = ();
    $App::Netdisco::Util::ManagedConfig::LOADED = undef;
  }

  return $calls;
}

1;
