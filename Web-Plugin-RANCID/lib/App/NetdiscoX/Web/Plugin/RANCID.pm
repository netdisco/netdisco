package App::NetdiscoX::Web::Plugin::RANCID;

our $VERSION = '2.001001';

use Dancer ':syntax';
use App::Netdisco::Web::Plugin;

use File::ShareDir 'dist_dir';
register_template_path(
  dist_dir( 'App-NetdiscoX-Web-Plugin-RANCID' ));

register_device_details({
  name  => 'rancid',
  label => 'RANCID',
  default => 'on',
});

=head1 NAME

App::NetdiscoX::Web::Plugin::RANCID - Link to device backups in RANCID/WebSVN

=head1 SYNOPSIS

 # in your ~/environments/deployment.yml file
  
 extra_web_plugins:
   - X::RANCID
 
 plugin_rancid:
   location: 'websvn-server.example.com/rancid'
   open_in_new_window: true

=head1 Description

This is a plugin for the L<App::Netdisco> network management application.
It adds a row to the Device Details page named "RANCID" with a link to
your local RANCID/WebSVN installation hosting the device configuation
backups.

=head1 Configuration

Create an entry in your C<~/environments/deployment.yml> file named
"C<plugin_rancid>", containing the following settings:

=head2 location

Value: String, Required.

Name of the server hosting your local WebSVN installation. This should
also include the path under which backup files are stored for the devices.

=head2 open_in_new_window

Value: Boolean. Default: false.

If set to true, the hyperlink is configured to open the WebSVN page in a new
browser window or tab.

=head1 TODO

At the moment the device name is used in the link. This is kind of useless
for most installations. Needs config to control how to specify device in
generated link.

=head1 AUTHOR

Oliver Gorwits <oliver@cpan.org>

=head1 COPYRIGHT AND LICENSE
 
This software is copyright (c) 2013 by The Netdisco Developer Team.
 
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

true;
