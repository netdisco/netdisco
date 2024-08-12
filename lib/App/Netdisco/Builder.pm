package App::Netdisco::Builder;

use strict;
use warnings;

use File::Spec; # core
use Module::Build;
@App::Netdisco::Builder::ISA = qw(Module::Build);

our $home;

BEGIN {
    $home = ($ENV{NETDISCO_HOME} || $ENV{HOME});
    $ENV{POETRY_CACHE_DIR} = File::Spec->catdir($home, 'python', 'cache', 'pypoetry');
}

sub ACTION_poetry {
    my $self = shift;
    require App::Netdisco::Util::Python;
    $self->do_system( App::Netdisco::Util::Python::py_install() );
}

sub ACTION_install {
    my $self = shift;
    $self->SUPER::ACTION_install;
    $self->ACTION_poetry;
}

1;
