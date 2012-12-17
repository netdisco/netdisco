package App::Netdisco;

use strict;
use warnings FATAL => 'all';
use 5.10.0;

use File::ShareDir 'module_dir';
use Path::Class;

our $VERSION = '2.00_009';

BEGIN {
  if (not length $ENV{DANCER_APPDIR}
      or not -f file($ENV{DANCER_APPDIR}, 'config.yml')) {

      my $auto = dir(File::ShareDir::module_dir('App::Netdisco'))->absolute;

      $ENV{DANCER_APPDIR}  ||= $auto->stringify;
      $ENV{DANCER_CONFDIR} ||= $auto->stringify;

      $ENV{DANCER_ENVDIR} ||= $auto->subdir('environments')->stringify;
      $ENV{DANCER_PUBLIC} ||= $auto->subdir('public')->stringify;
      $ENV{DANCER_VIEWS}  ||= $auto->subdir('views')->stringify;
  }
}

=head1 App::Netdisco

Netdisco is an Open Source web-based network management tool.

=head1 AUTHOR
 
Oliver Gorwits <oliver@cpan.org>
 
=head1 COPYRIGHT AND LICENSE
 
This software is copyright (c) 2012 by The Netdisco Developer Team.
 
This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

1;
