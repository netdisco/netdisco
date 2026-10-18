package Test::Netdisco::ManagedACL;

# Fake ACL Manager rows for tests that can't reach PostgreSQL. stub_managed_acls
# replaces App::Netdisco::Util::Configuration::_load_managed_acls, the one
# database read behind effective_setting, so the merge in _build_overlay and
# every check above it still run for real.

use strict;
use warnings;

use App::Netdisco::Util::Configuration ();

use base 'Exporter';
our @EXPORT_OK = qw/stub_managed_acls/;

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
  sub acl_type { 'host_port' }
  sub mappings { Test::Netdisco::ManagedACL::Maps->new(@{ $_[0]->{maps} }) } }

sub stub_managed_acls {
  my ($roles, %opts) = @_;
  my $id = $opts{first_id} || 1;
  my @names;

  foreach my $role (sort keys %{ $roles || {} }) {
    my @maps;
    foreach my $pair (@{ $roles->{$role} }) {
      my $left  = Test::Netdisco::ManagedACL::List->new(id => $id++, rules => $pair->[0]);
      my $right = ((scalar @$pair > 1)
        ? Test::Netdisco::ManagedACL::List->new(id => $id++, rules => $pair->[1]) : undef);
      push @maps, Test::Netdisco::ManagedACL::Map->new(
        id => scalar(@maps) + 1, left_acl => $left, right_acl => $right);
    }
    push @names, Test::Netdisco::ManagedACL::Name->new(acl_name => $role, maps => \@maps);
  }

  my $calls = 0;
  {
    no warnings 'redefine';
    *App::Netdisco::Util::Configuration::_load_managed_acls = sub {
      $calls++;
      die $opts{dies} if $opts{dies};
      return @names;
    };
  }
  # keep_cache changes what the database "holds" without dropping an overlay
  # already built, to show that something else (Worker::Runner) drops it
  App::Netdisco::Util::Configuration::forget_effective_config()
    unless $opts{keep_cache};
  return \$calls;
}

1;
