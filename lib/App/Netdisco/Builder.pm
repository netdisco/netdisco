package App::Netdisco::Builder;

use strict;
use warnings;

use Module::Build;
@App::Netdisco::Builder::ISA = qw(Module::Build);

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
