package Dancer::Template::NetdiscoTemplateToolkit;

use strict;
use warnings;

use Dancer::FileUtils 'path';
use base 'Dancer::Template::TemplateToolkit';

sub view {
    my ($self, $view) = @_;

    foreach my $path (@{ $self->config->{INCLUDE_PATH} }) {
        foreach my $template ($self->_template_name($view)) {
            my $view_path = path($path, $template);
            return $view_path if -f $view_path;
        }
    }

    # No matching view path was found
    return;
}

1;
