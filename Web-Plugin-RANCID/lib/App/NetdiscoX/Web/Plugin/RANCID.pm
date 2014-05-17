package App::NetdiscoX::Web::Plugin::RANCID;

our $VERSION = '2.003002';

use Dancer ':syntax';

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Util::Permission 'check_acl';

use File::ShareDir 'dist_dir';
register_template_path(
  dist_dir( 'App-NetdiscoX-Web-Plugin-RANCID' ));

register_device_details({
  name  => 'rancid',
  label => 'RANCID',
  default => 'on',
});

hook 'before_template' => sub {
    return unless
      index(request->path, uri_for('/ajax/content/device/details')->path) == 0;

    my $config = config;
    my $tokens = shift;
    my $device = $tokens->{d};

    # defaults
    $tokens->{rancidgroup} = '';
    $tokens->{ranciddevice} = ($device->{dns} || $device->{name} || $device->{ip});

    return unless exists $config->{rancid};
    my $rancid = $config->{rancid};

    $rancid->{groups} ||= {};
    $rancid->{by_ip}  ||= [];

    foreach my $g (keys %{ $rancid->{groups} }) {
        if (check_acl( get_device($device->{ip}), $rancid->{groups}->{$g} )) {
            $tokens->{rancidgroup} = $g;
            $tokens->{ranciddevice} = $device->{ip}
              if 0 < scalar grep {$_ eq $g} @{ $rancid->{by_ip} };
            last;
        }
    }
};

=head1 NAME

App::NetdiscoX::Web::Plugin::RANCID - Link to device backups in RANCID/WebSVN

=head1 SYNOPSIS

 # in your ~/environments/deployment.yml file
  
 extra_web_plugins:
   - X::RANCID
 
 plugin_rancid:
   location: 'https://websvn-server.example.com/rancid/%DEVICE%'

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

The text "C<%DEVICE%>" B<must> be included, and it will be substituted with
the name or IP of the device. That is, this setting must be a complete link to
a RANCID web page, only with the device name or ip changed to be
"C<%DEVICE%>".

The text "C<%GROUP%>" will be replaced with the group name for this device, if
known to Netdisco. This uses the same configuration as for
L<netdisco-rancid-export>, an example of which is below:

 rancid:
   by_ip:    [ other ]
   groups:
     switch: [ 'name:.*[Ss][Ww].*' ]
     rtr:    [ 'name:[rR]tr.*' ]
     ap:     [ 'name:[aA][pP].*' ]

Briefly, each group value is a list of rules for matching devices similar to
those used by any C<*_only> configuration item. You can provide an IP, subnet
or prefix, regular expression to match a device name, or device attribute and
regular expression as in the above example.

The device DNS name is used, or if missing the device SNMP sysName. Adding the
group to the list in C<by_ip> will make the link include the device IP
instead of the name.

=head2 open_in_same_window

Value: Boolean. Default: false.

If set to true, the hyperlink is configured to open the WebSVN page in the
same browser window or tab as Netdisco.

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
