package App::NetdiscoX::Web::Plugin::Observium;

our $VERSION = '2.003000';

use Dancer ':syntax';
use App::Netdisco::Web::Plugin;

use File::ShareDir 'dist_dir';
register_template_path(
  dist_dir( 'App-NetdiscoX-Web-Plugin-Observium' ));

register_device_port_column({
  name  => 'observium',
  position => 'mid',
  label => 'Traffic',
  default => 'on',
});

register_css('observium');
register_javascript('observium');

=head1 NAME

App::NetdiscoX::Web::Plugin::Observium - Port Traffic Links and Thumbnail Graphs from Observium

=head1 SYNOPSIS

 # in your ~/environments/deployment.yml file
  
 extra_web_plugins:
   - X::Observium
 
 plugin_observium:
   location: "https://web-server.example.com/"
   open_in_same_window: false

=head1 Description

This is a plugin for the L<App::Netdisco> network management application. It
adds a column to the Device Ports table named "Traffic" with a link and
thumbnail graph for the port, taken from a local Observium installation.

=head1 Configuration

Create an entry in your C<~/environments/deployment.yml> file named
"C<plugin_observium>", containing the following settings:

=head2 location

Value: String, Required.

Full URL to your local Observium server, including HTTP/HTTPS scheme (as in
the example above).

=head2 open_in_same_window

Value: Boolean. Default: false.

If set to true, the hyperlink is configured to open the port's Observium page
in the same browser window or tab as Netdisco. The default is false.

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
