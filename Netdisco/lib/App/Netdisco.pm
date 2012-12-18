package App::Netdisco;

use strict;
use warnings FATAL => 'all';
use 5.10.0;

use File::ShareDir 'dist_dir';
use Path::Class;

our $VERSION = '2.00_009';

BEGIN {
  if (not length $ENV{DANCER_APPDIR}
      or not -f file($ENV{DANCER_APPDIR}, 'config.yml')) {

      my $auto = dir(dist_dir('App-Netdisco'))->absolute;

      $ENV{DANCER_APPDIR}  ||= $auto->stringify;
      $ENV{DANCER_CONFDIR} ||= $auto->stringify;

      $ENV{DANCER_ENVDIR} ||= $auto->subdir('environments')->stringify;
      $ENV{DANCER_PUBLIC} ||= $auto->subdir('public')->stringify;
      $ENV{DANCER_VIEWS}  ||= $auto->subdir('views')->stringify;
  }
}

=head1 NAME

App::Netdisco - An open source web-based network management tool.

=head1 Introduction

The contents of this distribution is the next major version of the Netdisco
network management tool. See L<http://netdisco.org/> for further information
on the project.

If you have any trouble getting the frontend running, or it blows up in your
face, please speak to someone in the C<#netdisco> IRC channel (on freenode).

=head1 Installation

Netdisco has several Perl library dependencies which will be automatically
installed. However it's I<strongly> recommended that you first install
L<DBD::Pg> and L<SNMP> using your operating system packages. The following
commands will test for the existence of them on your system:

 perl -MDBD::Pg\ 999
 perl -MSNMP\ 999

With that done, we can proceed...

To avoid muddying your system, use the following script to download and
install Netdisco and its dependencies into your home area:

 curl -L http://cpanmin.us/ | perl - \
     --notest --quiet --local-lib ${HOME}/perl-profiles/netdisco" \
     App::cpanminus \
     App::local::lib::helper \
     App::Netdisco

Test the installation by running the following command, which should only
produce some help text (and throw up no errors):

 ~/perl-profiles/netdisco/bin/localenv netdisco-daemon --help

=head1 Configuration

Netdisco uses a PostgreSQL (Pg) database. You can use this application with an
existing database, or set up a new one. At a minimum (if starting from
scratch) you should have created a Database in Pg, and created a User in Pg
with rights on the Database:

 postgres:~$ createuser -DRSP netdisco
 postgres:~$ createdb -O netdisco netdisco

Make a directory for your local configuration, and copy the
C<share/environments/development.yml> file from this distribution into it.
Edit the file and change the database connection parameters for your local
system (the C<dsn>, C<user> and C<pass>).

Optionally, in the same file uncomment and edit the C<domain_suffix> setting
to be appropriate for your local site (same as the C<domain> setting in
C<netdisco.conf>).

Finally, run the following script to bring you up to date:

 ~/perl-profiles/netdisco/bin/localenv netdisco-db-deploy

=head1 Startup

Make a note of the directory containing C<development.yml> and run the
following command to start the web server, substituting as appropriate:

 DANCER_ENVIRONMENT=/change/me/dir ~/perl-profiles/netdisco/bin/localenv netdisco-web

=head1 Tips and Tricks

The main black navigation bar has a search box which is smart enough to work
out what you're looking for in most cases. For example device names, node IP
or MAC addreses, VLAN numbers, and so on.

For SQL debugging try the following command:

 DBIC_TRACE_PROFILE=console DBIC_TRACE=1 \
   DANCER_ENVIRONMENT=/change/me/dir \
   ~/perl-profiles/netdisco/bin/localenv netdisco-web

=head1 Future Work

The intention is to support "plugins" for additonal features, most notably
columns in the Device Port listing, but also new menu items and tabs. The
design of this is sketched out but not implemented. The goal is to avoid
patching core code to add localizations or less widely used features.

Bundled with this app is a L<DBIx::Class> layer for the Netdisco database.
This could be a starting point for an "official" DBIC layer. Helper functions
and canned searches have been added to support the web interface.

=head1 Caveats

Some sections are not yet implemented, e.g. the I<Device Module> tab.

Menu items on the main black navigation bar go nowhere, except Home.

None of the Reports yet exist (e.g. searching for wireless devices, or duplex
mismatches). These might be implemented as a plugin bundle.

The Wireless, IP Phone and NetBIOS Node properies are not yet shown.

=head1 AUTHOR
 
Oliver Gorwits <oliver@cpan.org>
 
=head1 COPYRIGHT AND LICENSE
 
This software is copyright (c) 2012 by The Netdisco Developer Team.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the Netdisco Project nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE NETDISCO DEVELOPER TEAM BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

1;
