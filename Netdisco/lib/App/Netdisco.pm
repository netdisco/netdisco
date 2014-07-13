package App::Netdisco;

use strict;
use warnings;
use 5.010_000;

our $VERSION = '2.028002_001';
use App::Netdisco::Configuration;

=head1 NAME

App::Netdisco - An open source web-based network management tool.

=head1 Introduction

Netdisco is a web-based network management tool designed for network
administrators. Data is collected into a PostgreSQL database using SNMP.

Some of the things you can do with Netdisco:

=over 4

=item *

B<Locate> a machine on the network by MAC or IP and show the switch port it
lives at

=item *

B<Turn off> a switch port, or change the VLAN or PoE status of a port

=item *

B<Inventory> your network hardware by model, vendor, software and operating
system

=item *

B<Pretty pictures> of your network

=back

L<App::Netdisco> provides a web frontend with built-in web server, and a
backend daemon to handle interactive requests such as changing port or device
properties.

=over 4

=item *

See the demo at: L<http://netdisco2-demo.herokuapp.com/>

=back

If you have any trouble getting installed or running, check out the
L<Deployment|App::Netdisco::Manual::Deployment> notes, or speak to someone in
the C<#netdisco> IRC channel (on freenode).  Before installing or upgrading
please always review the latest L<Release
Notes|App::Netdisco::Manual::ReleaseNotes>.

=head1 Dependencies

Netdisco has several Perl library dependencies which will be automatically
installed. However it's I<strongly> recommended that you first install
L<DBD::Pg>, L<SNMP>, and a compiler using your operating system packages.

On Ubuntu/Debian:

 root:~# apt-get install libdbd-pg-perl libsnmp-perl build-essential

On Fedora/Red-Hat:

 root:~# yum install perl-core perl-DBD-Pg net-snmp-perl make automake gcc

With those installed, we can proceed...

Create a user on your system called C<netdisco> if one does not already exist.
We'll install Netdisco and its dependencies into this user's home area, which
will take about 250MB including MIB files.

 root:~# useradd -m -p x -s /bin/bash netdisco

Netdisco uses the PostgreSQL database server. Install PostgreSQL (at least
version 8.4) and then change to the PostgreSQL superuser (usually
C<postgres>). Create a new database and PostgreSQL user for the Netdisco
application:

 root:~# su - postgres
  
 postgres:~$ createuser -DRSP netdisco
 Enter password for new role:
 Enter it again:
  
 postgres:~$ createdb -O netdisco netdisco

The default PostgreSQL configuration isn't well tuned for modern server
hardware. We strongly recommend that you use the C<pgtune> Python program to
auto-tune your C<postgresql.conf> file:

=over 4

=item *

L<https://github.com/elitwin/pgtune>

=back

=head1 Installation

The following is a general guide which works well in most circumstances. It
assumes you have a user C<netdisco> on your system, that you want to perform
an on-line installation, and have the application run self-contained from
within that user's home. There are alternatives: see the
L<Deployment|App::Netdisco::Manual::Deployment> documentation for further
details.

To avoid muddying your system, use the following script to download and
install Netdisco and its dependencies into the C<netdisco> user's home area
(C<~netdisco/perl5>):

 su - netdisco
 curl -L http://cpanmin.us/ | perl - --notest --local-lib ~/perl5 App::Netdisco

Link some of the newly installed apps into a handy location:

 mkdir ~/bin
 ln -s ~/perl5/bin/{localenv,netdisco-*} ~/bin/

Test the installation by running the following command, which should only
produce a status message (it's just a test - you'll start the daemon properly,
later on):

 ~/bin/netdisco-daemon status

=head1 Configuration

Make a directory for your local configuration and copy the configuration
template from this distribution:

 mkdir ~/environments
 cp ~/perl5/lib/perl5/auto/share/dist/App-Netdisco/environments/deployment.yml ~/environments
 chmod 600 ~/environments/deployment.yml

Edit the file ("C<~/environments/deployment.yml>") and change the database
connection parameters to match those for your local system (that is, the
C<name>, C<user> and C<pass>).

In the same file uncomment and edit the C<domain_suffix> setting to be
appropriate for your local site.

Change the C<community> string setting if your site has different values, and
uncomment the C<schedule> setting to enable SNMP data gathering from
devices (this replaces cron jobs in Netdisco 1).

Have a quick read of the other settings to make sure you're happy, then move
on. See L<Configuration|App::Netdisco::Manual::Configuration> for further
details.

=head1 Bootstrap

The database either needs configuring if new, or updating from the current
release of Netdisco (1.x). You also need vendor MAC address prefixes (OUI
data) and some MIBs if you want to run the daemon. The following script will
take care of all this for you:

 ~/bin/netdisco-deploy

If this is a new installation of Netdisco 2, answer yes to all questions. If
you wish to deploy without Internet access, see the
L<Deployment|App::Netdisco::Manual::Deployment> documentation.

=head1 Startup

Run the following command to start the web-app server as a backgrounded daemon
(listening on port 5000):

 ~/bin/netdisco-web start

Run the following command to start the job control daemon (port control, etc):

 ~/bin/netdisco-daemon start

You should take care not to run this Netdisco daemon and the Netdisco 1.x
daemon at the same time. Similarly, if you use the device discovery with
Netdisco 2, disable your system's cron jobs for the Netdisco 1.x poller.

For further documentation on deployment, see
L<Deployment|App::Netdisco::Manual::Deployment>.

=head1 Upgrading

Before upgrading please review the latest L<Release
Notes|App::Netdisco::Manual::ReleaseNotes>. Then, the process is as follows:

 # upgrade Netdisco
 ~/bin/localenv cpanm --notest App::Netdisco
 
 # apply database schema updates
 ~/bin/netdisco-deploy
 
 # restart web service
 ~/bin/netdisco-web restart
 
 # restart job daemon (if you use it)
 ~/bin/netdisco-daemon restart

=head1 Tips and Tricks

=head2 Searching

The main black navigation bar has a search box which is smart enough to work
out what you're looking for in most cases. For example device names, node IP
or MAC addreses, VLAN numbers, and so on.

=head2 Command-Line Device and Port Actions

To run a device (discover, etc) or port control job from the command-line, use
the bundled L<netdisco-do> program. For example:

 ~/bin/netdisco-do -D discover -d 192.0.2.1

=head2 Import Topology

Netdisco 1.x had support for a topology information file to fill in device
port relations which could not be discovered. This is now stored in the
database (and edited in the web interface). To import a legacy topology file,
run:

 ~/bin/localenv nd-import-topology /path/to/netdisco-topology.txt

=head2 Database API

Bundled with this distribution is a L<DBIx::Class> layer for the Netdisco
database. This abstracts away all the SQL into an elegant, re-usable OO
interface. See the L<Developer|App::Netdisco::Manual::Developing>
documentation for further information.

=head2 Plugins

Netdisco includes a Plugin subsystem for customizing the web user interface.
See L<App::Netdisco::Web::Plugin> for further information.

=head2 Developing

Lots of information about the architecture of this application is contained
within the L<Developer|App::Netdisco::Manual::Developing> documentation.

=head1 AUTHOR

Oliver Gorwits <oliver@cpan.org>

=head1 COPYRIGHT AND LICENSE
 
This software is copyright (c) 2012, 2013, 2014 by The Netdisco Developer Team.
 
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
