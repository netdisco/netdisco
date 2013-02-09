package App::Netdisco::Web::Plugin;

use Dancer ':syntax';
use Dancer::Plugin;

set(
  'navbar_items' => [],
  'search_tabs'  => [],
  'device_tabs'  => [],
);

register 'register_navbar_item' => sub {
  my ($self, $config) = plugin_args(@_);

  die "bad config to register_navbar_item\n"
    unless length $config->{id}
       and length $config->{path}
       and length $config->{label};

  foreach my $item (@{ setting('navbar_items') }) {
      if ($item->{id} eq $config->{id}) {
          $item = $config;
          return;
      }
  }

  push @{ setting('navbar_items') }, $config;
};

sub _register_tab {
  my ($nav, $config) = @_;
  my $stash = setting("${nav}_tabs");

  die "bad config to register_${nav}_tab\n"
    unless length $config->{id}
       and length $config->{label};

  foreach my $item (@{ $stash }) {
      if ($item->{id} eq $config->{id}) {
          $item = $config;
          return;
      }
  }

  push @{ $stash }, $config;
}

register 'register_search_tab' => sub {
  my ($self, $config) = plugin_args(@_);
  _register_tab('search', $config);
};

register 'register_device_tab' => sub {
  my ($self, $config) = plugin_args(@_);
  _register_tab('device', $config);
};

register_plugin;
true;

=head1 NAME

App::Netdisco::Web::Plugin - Plugin subsystem for App::Netdisco Web UI components

=head1 Introduction

L<App::Netdisco>'s plugin subsystem allows developers to write and test web
user interface (UI) components without needing to patch the main Netdisco
application. It also allows the end-user more control over the UI components
displayed in their browser.

So far, the following UI compoents are implemented as plugins:

=over 4

=item *

Navigation Bar items (e.g. Inventory link)

=item *

Tabs for Search and Device pages

=back

In the future there will be other components supported, such as Reports.

This document explains first how to configure which plugins are loaded (useful
for the end-user) and then also how to write and install your own plugins.

=head1 Application Configuration

In the main C<config.yml> file for App::Netdisco (located in C<share/...>)
you'll find the C<web_plugins> configuration directive. This lists, in YAML
format, a set of Perl module names (or partial names) which are the plugins to
be loaded. For example:

 web_plugins:
   - Inventory
   - Search::Device
   - Search::Node
   - Search::Port
   - Device::Details
   - Device::Ports

When the name is specified as above, App::Netdisco automatically prepends
"C<App::Netdisco::Web::Plugin::>" to the name. This makes, for example,
L<App::Netdisco::Web::Plugin::Inventory>. This is the module which is loaded
to add a user interface component.

Such plugin modules can either ship with the App::Netdisco distribution
itself, or be installed separately. Perl uses the standard C<@INC> path
searching mechanism to load the plugin modules.

If an entry in the C<web_plugins> list starts with a "C<+>" (plus) sign then
App::Netdisco attemps to load the module as-is, without prepending anything to
the name. This allows you to have App::Netdiso web UI plugins in other
namespaces:

 web_plugins:
   - Inventory
   - Search::Device
   - Search::Node
   - Device::Details
   - Device::Ports
   - +My::Other::Netdisco::Web::Component

The order of the entries in C<web_plugins> is significant. Surprisingly
enough, the modules are loaded in order. Therefore Navigation Bar items appear
in the order listed, and Tabs appear on the Search and Device pages in the
order listed.

The consequence of this is that if you want to change the order (or add or
remove entries) then simply edit the C<web_plugins> setting. In fact, we
recommend adding this setting to your C<< <environment>.yml >> file and
leaving the C<config.yml> file alone. Your Environment's version will take
prescedence.

Finally, if you want to add components without completely overriding the
C<web_plugins> setting, use the C<extra_web_plugins> setting instead in your
Environment configuration. Any Navigation Bar items or Page Tabs are added
after those in C<web_plugins>.

=head1 Developing Plugins

A plugin is simply a Perl module which is loaded. Therefore it can do anything
you like, but most usefully for the App::Netdisco web application, the module
will install a L<Dancer> route handler subroutine, and link this to a web user
interface (UI) component.

Explaining how to write Dancer route handlers is beyond the scope of this
document, but by examining the source to the plugins in App::Netdisco you'll
probably get enough of an idea to begin on your own.

App::Netdisco plugins should load the L<App::Netdisco::Web::Plugin> module.
This exports a set of helper subroutines to register the new UI components.
Here's the boilerplate code for our example plugin module:

 package App::Netdisco::Web::Plugin::MyNewFeature
 
 use Dancer ':syntax';
 use Dancer::Plugin::Ajax;
 use Dancer::Plugin::DBIC;
 
 use App::Netdisco::Web::Plugin;
 
 # plugin registration code goes here, ** see below **
 
 # your Dancer route handler, for example:
 get '/mynewfeature' => sub {
   # ...lorem ipsum...
 };
 
 true;

=head2 Navigation Bar items

These components appear in the black navigation bar at the top of each page,
as individual items (i.e. not in a menu). The canonical example of this is the
Inventory link.

To register an item for display in the navigation bar, use the following code:

 register_navbar_item({
   id    => 'newfeature',
   path  => '/mynewfeature',
   label => 'My New Feature',
 });

This causes an item to appear in the Navigation Bar with a visible text of "My
New Feature" which when clicked sends the user to the C</mynewfeature> page.
Note that this won't work for any target link - the path must be an
App::Netdisco Dancer route handler. Please bug the App::Netdisco devs if you
want arbitrary links supported.

=head2 Search and Device page Tabs

These components appear as tabs in the interface when the user reaches the
Search page or Device details page. If you add a new tab, remember that the
C<package> name in the file should be C<...Plugin::Device::MyNewFeature> (i.e.
within the Device namespace).

To register an item for display as a Search page Tab, use the following code:

 register_search_tab({id => 'newfeature', label => 'My New Feature'});

This causes a tab to appear with the label "My New Feature". So how does
App::Netdisco know what the link should be? Well, as the
L<App::Netdisco::Developing> documentation says, tab content is retrieved by
an AJAX call back to the web server. This uses a predictable URL path format:

 /ajax/content/<search or device>/<feature ID>

For example:

 /ajax/content/search/newfeature

Therefore your plugin module should look like the following:

 ajax '/ajax/content/search/newfeature' => sub {
   # ...lorem ipsum...

   content_type('text/html');
   # return some HTML content here, probably using a template
 };

If this all sounds a bit daunting, take a look at the
L<App::Netdisco::Web::Plugin::Search::Port> module which is fairly
straightforward.

To register an item for display as a Device page Tab, the only difference is
the name of the registration helper sub:

 register_device_tab({id => 'newfeature', label => 'My New Feature'});

=head1 Templates

All of Netdisco's web page templates are stashed away in its distribution,
probably installed in your system's or user's Perl directory. It's not
recommended that you mess about with these files.

So in order to replace a template with your own version, or to reference a
template file of your own in your plugin, you need a new path.

TODO: this bit!

=head2 Template Variables

Some useful variables are made available in your templates automatically by
App::Netdisco:

=over 4

=item  C<search_node>

A base url which links to the Node tab of the Search page, together with the
correct default search options set.

=item  C<search_device>

A base url which links to the Device tab of the Search page, together with the
correct default search options set.

=item  C<device_ports>

A base url which links to the Ports tab of the Device page, together with
the correct default column view options set.

=item  C<uri_base>

Used for linking to static content within App::Netdisco safely if the base of
the app is relocated, for example:

 <link rel="stylesheet" href="[% uri_base %]/css/toastr.css"/>

=item  C<uri_for>

Simply the Dancer C<uri_for> method. Allows you to do things like this in the
template safely if the base of the app is relocated:

 <a href="[% uri_for('/search') %]" ...>

=item  C<self_options>

Available in the Device tabs, use this if you need to refer back to the
current page with some additional parameters, for example:

 <a href="[% uri_for('/device', self_options) %]&foo=bar" ...>

=back

=cut

