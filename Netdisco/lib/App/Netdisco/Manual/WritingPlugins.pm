=head1 NAME

App::Netdisco::Manual::WritingPlugins - Documentation on Plugins for Developers

=head1 Introduction

L<App::Netdisco>'s plugin subsystem allows developers to write and test web
user interface (UI) components without needing to patch the main Netdisco
application. It also allows the end-user more control over the UI components
displayed in their browser.

See L<App::Netdisco::Web::Plugin> for more general information about plugins.

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

=head1 Navigation Bar items

These components appear in the black navigation bar at the top of each page,
as individual items (i.e. not in a menu). The canonical example of this is the
Inventory link.

To register an item for display in the navigation bar, use the following code:

 register_navbar_item({
   tag   => 'newfeature',
   path  => '/mynewfeature',
   label => 'My New Feature',
 });

This causes an item to appear in the Navigation Bar with a visible text of "My
New Feature" which when clicked sends the user to the C</mynewfeature> page.
Note that this won't work for any target link - the path must be an
App::Netdisco Dancer route handler. Please bug the App::Netdisco devs if you
want arbitrary links supported.

=head1 Search and Device page Tabs

These components appear as tabs in the interface when the user reaches the
Search page or Device details page. Note that Tab plugins usually live in
the C<App::Netdisco::Web::Plugin::Device> or
C<App::Netdisco::Web::Plugin::Search> namespace.

To register a handler for display as a Search page Tab, use the following
code:

 register_search_tab({tag => 'newfeature', label => 'My New Feature'});

This causes a tab to appear with the label "My New Feature". So how does
App::Netdisco know what the link should be? Well, as the
L<App::Netdisco::Developing> documentation says, tab content is retrieved by
an AJAX call back to the web server. This uses a predictable URL path format:

 /ajax/content/<search or device>/<feature tag>

For example:

 /ajax/content/search/newfeature

Therefore your plugin module should look like the following:

 package App::Netdisco::Web::Plugin::Search::MyNewFeature
 
 use Dancer ':syntax';
 use Dancer::Plugin::Ajax;
 use Dancer::Plugin::DBIC;
 
 use App::Netdisco::Web::Plugin;
 
 register_search_tab({tag => 'newfeature', label => 'My New Feature'});
 
 ajax '/ajax/content/search/newfeature' => sub {
   # ...lorem ipsum...
 
   content_type('text/html');
   # return some HTML content here, probably using a template
 };
 
 true;

If this all sounds a bit daunting, take a look at the
L<App::Netdisco::Web::Plugin::Search::Port> module which is fairly
straightforward.

To register a handler for display as a Device page Tab, the only difference is
the name of the registration helper sub:

 register_device_tab({tag => 'newfeature', label => 'My New Feature'});

=head1 Reports

Report components contain pre-canned searches which the user community have
found to be useful. The implementation is very similar to one of the Search
and Device page Tabs, so please read that documentation above, first.

Report plugins usually live in the C<App::Netdisco::Web::Plugin::Report>
namespace. To register a handler for display as a Report, you need to pick the
I<category> of the report. Here are the pre-defined categories:

=over 4

=item *

Device

=item *

Port

=item *

Node

=item *

VLAN

=item *

Network

=item *

Wireless

=back

Once your category is selected, use the following registration code:

 register_report({
   category => 'Port', # pick one from the list
   tag => 'newreport',
   label => 'My New Report',
 });

You will note that like Device and Search page Tabs, there's no path
specified in the registration. The reports engine will make an AJAX request to
the following URL:

 /ajax/content/report/<report tag>

Therefore you should implement in your plugin an AJAX handler for this path.
The handler must return the HTML content for the report. It can also process
any query parameters which might customize the report search.

See the L<App::Netdisco::Web::Plugin::Report::DuplexMismatch> module for a
simple example of how to implement the handler.

=head1 Templates

All of Netdisco's web page templates are stashed away in its distribution,
probably installed in your system's or user's Perl directory. It's not
recommended that you mess about with those files.

So in order to replace a template with your own version, or to reference a
template file of your own in your plugin, you need a new path:

 package App::Netdisco::Web::Plugin::Search::MyNewFeature
  
 use File::ShareDir 'dist_dir';
 register_template_path(
   dist_dir( 'App-Netdisco-Web-Plugin-Search-MyNewFeature' ));

The registered path will be searched before the built-in C<App::Netdisco>
path. We recommend use of the L<File::ShareDir> module to package and ship
templates along with your plugin, as shown.

Each path added using C<register_template_path> is searched I<before> any
existing paths in the template config.

=head3 Template Variables

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

