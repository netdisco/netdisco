package Test::Netdisco::LoadRecorder;

# Loaded first (perl -MTest::Netdisco::LoadRecorder), records which module
# loaded each module, for xt/bin/cpan-audit-coverage. Writes "module<TAB>loader"
# lines to the file named in $ENV{LOAD_RECORD}: from CHECK, because perl -c
# never runs END, and from END, for modules required at run time.

use strict;
use warnings;

my %loader_of;

# The calling file, not caller's package: a file's first `use` lines run
# before its `package` statement, so the package there is its loader's.
unshift @INC, sub {
  my (undef, $file) = @_;
  return if exists $loader_of{$file};
  my (undef, $caller_file) = caller(0);
  # a failed require leaves its %INC entry undef
  my %module_at = map { defined $INC{$_} ? ($INC{$_} => $_) : () } keys %INC;
  $loader_of{$file} = $module_at{$caller_file} // $caller_file;
  return;
};

sub _module { (my $name = shift) =~ s{/}{::}g; $name =~ s{\.pm$}{}; return $name }

sub _write {
  my $record = $ENV{LOAD_RECORD} or return;
  open my $out, '>>', $record or die "cannot append to $record: $!\n";
  foreach my $file (grep { m/\.pm$/ and defined $INC{$_} } keys %INC) {
    my $loader = $loader_of{$file} // 'perl, before the recorder';
    $loader = _module($loader) if $loader =~ m/\.pm$/;
    print {$out} _module($file), "\t$loader\n";
  }
  close $out;
}

CHECK { _write() }
END { _write() }

1;
