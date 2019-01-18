package App::Netdisco;

use strict;
use warnings;
use 5.010_000;

our $VERSION = '2.040003';
use App::Netdisco::Configuration;

=head1 NAME

App::Netdisco - An open source web-based network management tool.

=head1 DESCRIPTION

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
backend daemon to gather information from your network, and handle
interactive requests such as changing port or device properties.

=over 4

=item *

See the demo at: L<https://netdisco2-demo.herokuapp.com/>

=item *

L<Docker images|https://store.docker.com/community/images/netdisco/netdisco> are also available

=back

We have several other pages with tips for
L<alternate deployment scenarios|https://github.com/netdisco/netdisco/wiki/Install-Tips>,
L<understanding and troubleshooting Netdisco|https://github.com/netdisco/netdisco/wiki/Troubleshooting>,
L<tips and tricks for specific platforms|https://github.com/netdisco/netdisco/wiki/Vendor-Tips>,
and L<all the configuration options|https://github.com/netdisco/netdisco/wiki/Configuration>.

You can also speak to someone in the C<#netdisco@freenode> IRC channel, or on
the L<community email list|https://lists.sourceforge.net/lists/listinfo/netdisco-users>.
Before installing or upgrading please always review the latest
L<Release Notes|https://github.com/netdisco/netdisco/wiki/Release-Notes>.

=head1 Dependencies

Netdisco has several Perl library dependencies which will be automatically
installed. However it's I<strongly> recommended that you first install
L<DBD::Pg>, L<SNMP>, and a compiler using your operating system packages.

On Ubuntu/Debian:

 root:~# apt-get install libdbd-pg-perl libsnmp-perl libssl-dev libio-socket-ssl-perl build-essential

On Fedora/Red-Hat:

 root:~# yum install perl-core perl-DBD-Pg net-snmp-perl net-snmp-devel openssl-devel make automake gcc

On BSD systems please see L<our BSD tips|https://github.com/netdisco/netdisco/wiki/BSD-Install>.

With those installed, please check that your system's clock is correct.

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
L<Deployment|https://github.com/netdisco/netdisco/wiki/Install-Tips>
documentation for further details.

To avoid muddying your system, use the following script to download and
install Netdisco and its dependencies into the C<netdisco> user's home area
(C<~/perl5>):

 su - netdisco
 curl -L https://cpanmin.us/ | perl - --notest --local-lib ~/perl5 App::Netdisco

Link some of the newly installed apps into a handy location:

 mkdir ~/bin
 ln -s ~/perl5/bin/{localenv,netdisco-*} ~/bin/

Test the installation by running the following command, which should only
produce a status message (it's just a test - you'll start the daemons
properly, later on):

 ~/bin/netdisco-backend status

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
appropriate for your local site. Change the C<community> string setting if
your site has different values.

Have a quick read of the other settings to make sure you're happy, then move
on. See
L<Configuration|https://github.com/netdisco/netdisco/wiki/Configuration> for
further details.

=head1 Initialisation

The database either needs configuring if new, or updating from the current
release of Netdisco (1.x). You also need vendor MAC address prefixes (OUI
data) and some MIBs if you want to run the backend daemon. The following
script will take care of all this for you:

 ~/bin/netdisco-deploy

If this is a new installation of Netdisco 2, answer yes to all questions. If
you wish to deploy without Internet access, see the
L<Deployment|https://github.com/netdisco/netdisco/wiki/Install-Tips>
documentation.

=head1 Startup

Run the following command to start the web-app server as a background process:

 ~/bin/netdisco-web start

The web app listens on port 5000 (for example C<< http://localhost:5000/ >> or
C<< http://yourhost.example.com:5000/ >>).

Run the following command to start the job control daemon (device polling,
port control, etc):

 ~/bin/netdisco-backend start

I<note:> Whenever you upgrade your operating system, you should delete the
C<~/perl5> directory and re-run the C<curl> command above, to update
Netdisco's C library bindings.

I<also note:> You should take care not to run C<< netdisco-backend >> and the
Netdisco 1.x daemon at the same time. Similarly, if you use the device
discovery with Netdisco 2, disable your system's cron jobs for the Netdisco
1.x poller.

We have several other pages with tips for
L<alternate deployment scenarios|https://github.com/netdisco/netdisco/wiki/Install-Tips>,
L<understanding and troubleshooting Netdisco|https://github.com/netdisco/netdisco/wiki/Troubleshooting>,
L<tips and tricks for specific platforms|https://github.com/netdisco/netdisco/wiki/Vendor-Tips>,
and L<all the configuration options|https://github.com/netdisco/netdisco/wiki/Configuration>.

You can also speak to someone in the C<#netdisco@freenode> IRC channel, or on
the L<community email list|https://lists.sourceforge.net/lists/listinfo/netdisco-users>.
Before installing or upgrading please always review the latest
L<Release Notes|https://github.com/netdisco/netdisco/wiki/Release-Notes>.

=head1 Upgrading from 2.x

If you're running a version of Netdisco prior to 2.x then you should follow
the full installation instructions, above. This process is for upgrading
version 2.x only.

Before upgrading please review the latest L<Release Notes|https://github.com/netdisco/netdisco/wiki/Release-Notes>.
Then the process below should be run for each installation:

 # upgrade Netdisco
 ~/bin/localenv cpanm --notest App::Netdisco
 ln -sf ~/perl5/bin/{localenv,netdisco-*} ~/bin/
 
 # apply database schema updates, update MIBs and Vendor MACs
 ~/bin/netdisco-deploy
 
 # restart web service (if you run it)
 ~/bin/netdisco-web restart
 
 # restart the backend workers (wherever you run them)
 ~/bin/netdisco-backend restart

=head1 Tips and Tricks

=head2 Searching

The main black navigation bar has a search box which is smart enough to work
out what you're looking for in most cases. For example device names, node IP
or MAC addreses, VLAN numbers, and so on.

=head2 Command-Line Device and Port Actions

Most significant Device jobs and Port actions, as well as several
troubleshooting and housekeeping duties, can be performed at the command-line
with the L<netdisco-do> program. For example:

 ~/bin/netdisco-do -D discover -d 192.0.2.1

See the L<netdisco-do documentation|netdisco-do> for further details.

=head2 Import Topology

Netdisco 1.x had support for a topology information file to fill in device
port relations which could not be discovered. This is now stored in the
database (and edited in the web interface). To import a legacy topology file,
run:

 ~/bin/localenv nd-import-topology /path/to/netdisco-topology.txt

=head2 Database API

Bundled with this distribution is a L<DBIx::Class> layer for the Netdisco
database. This abstracts away all the SQL into an elegant, re-usable OO
interface. See the L<Developer|https://github.com/netdisco/netdisco/wiki/Developing>
documentation for further information.

=head2 Plugins

Netdisco includes a Plugin subsystem for customizing the web user interface and backend daemon.
See L<Web Plugins|https://github.com/netdisco/netdisco/wiki/Web-Plugins>
and L<Backend Plugins|https://github.com/netdisco/netdisco/wiki/Backend-Plugins>
for further information.

=head2 Extensions

Using the Plugins mechanism, it's also easy to write new commands (or actions)
for Netdisco. For example, an action has been added to L<generate RANCID
configuration|App::Netdisco::Worker::Plugin::MakeRancidConf>.

=head2 Developing

Lots of information about the architecture of this application is contained
within the L<Developer|https://github.com/netdisco/netdisco/wiki/Developing> documentation.

=head1 AUTHOR

Oliver Gorwits <oliver@cpan.org>

=head1 CONTRIBUTORS

Netdisco was created at the University of California, Santa Cruz (UCSC),
Networking and Technology Services (NTS) department. UCSC continues to support
the development of Netdisco by providing development servers and beer.

Original development by Max Baker, with significant contributions from Mark
Boolootian and Jim Warner (through whose ideas Netdisco was born and shaped),
Bill Fenner, Jeroen van Ingen, Eric Miller, Carlos Vicente, and Brian de Wolf.

Other contributions (large and small) by Mike Hunter (UCB), Brian Wilson
(NCSU), Bradley Baetz (bbaetz), David Temkin (sig.com), Edson Manners (FSU),
Dmitry Sergienko (Trifle Co, .ua), Remo Rickli (PSI, Switzerland),
Jean-Philippe Luiggi (sagem.com), A.L.M Buxey (Loughborough University, UK),
Kevin Cheek (UMICH), John Bigrow (bnl.gov), George Pavel (llnl.gov), Charles
Goldsmith (wokka.org), Douglas M.  McKeown (saintmarys.edu), Revital Shvarzman
(York U, Ontario), Walter Gould (Auburn U), Lindsay Druet and Colin Palmer (U
of Waikato, Hamilton NZ), Dusty Hall (Auburn U), Jon Monroe (center pointe),
Alexander Barthel, Bill Anderson, Alexander Hartmaier (t-systems.at), Justin
Hunter (Arizona State U), Jethro Binks (U of Strathclyde, Glasgow), Jordi
Guijarro (UAB.es), Sam Stickland (spacething.org),  Stefan Radman (CTBTO.org),
Clint Wise, Max Kosmach, Bernhard Augenstein and Nick Nauwelaerts (aquafin.be).

We probably forgot some names - sorry about that :-(.

Deep gratitude also goes
to the authors and communities of all the other software that Netdisco is
built upon.

=head1 COPYRIGHT AND LICENSE
 
This software is copyright (c) 2011-2018 by The Netdisco Developer Team.
 
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
