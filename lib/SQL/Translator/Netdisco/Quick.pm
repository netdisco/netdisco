package SQL::Translator::Netdisco::Quick;

use strict;
use warnings;

{
    package # hide from toolchain
        SQL::Translator::Netdisco::Quick::Table;
    use base 'SQL::Translator::Schema::Table';

    sub new {
        my ($class, $self) = @_;
        return bless $self, $class;
    };

    sub f {
        my $self = shift;
        return $self->{nd2_f} if $self->{nd2_f};
        $self->{nd2_f} = { map {($_->name => $_)} ($self->get_fields) };
        return $self->{nd2_f};
    }
}

use base 'SQL::Translator::Schema';

sub new {
    my ($class, $self) = @_;
    return bless $self, $class;
};

sub t {
    my $self = shift;
    return $self->{nd2_t} if $self->{nd2_t};
    $self->{nd2_t} = {
        (map {($_->name => SQL::Translator::Netdisco::Quick::Table->new($_))}
            $self->get_tables),
    };
    return $self->{nd2_t};
}

1;
