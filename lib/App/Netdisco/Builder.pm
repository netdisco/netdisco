package App::Netdisco::Builder;

use strict;
use warnings;

use File::Spec; # core
use Module::Build;
use CPAN::Changes;
use Perl::Version;
use Module::Metadata;

@App::Netdisco::Builder::ISA = qw(Module::Build);

sub ACTION_distmeta {
    my $self = shift;

    # delete the old MANIFEST file if it exists
    if (-e 'MANIFEST') {
        print "Removing old MANIFEST...\n";
        unlink 'MANIFEST' or print STDERR "Could not remove MANIFEST: $!";
    }

    # run the internal manifest action to generate a fresh one
    print "Generating fresh MANIFEST...\n";
    $self->depends_on('manifest');

    print "Bumping version from Changes...\n";
    my $changes = CPAN::Changes->load("Changes");
    my ($latest_release) = reverse $changes->releases;
    my $version = ($latest_release->version || $ENV{NETDISCO_RELEASE_VERSION});
    die "failed to find version in Changes file or environment\n" unless $version;
    system('perl-reversion', '-set', $version, 'lib/App/Netdisco.pm');

    # Also force Module::Build to refresh its internal version property
    # so the generated META files use the new bumped value.
    $self->{properties}{dist_version}
        = Module::Metadata->new_from_file('lib/App/Netdisco.pm')->version;

    $self->SUPER::ACTION_distmeta(@_);
}

sub ACTION_python {
    my $self = shift;
    require App::Netdisco::Util::Python;
    $self->do_system( App::Netdisco::Util::Python::py_install() );
}

sub ACTION_install {
    my $self = shift;
    $self->SUPER::ACTION_install;
    $self->ACTION_python;
}

1;
