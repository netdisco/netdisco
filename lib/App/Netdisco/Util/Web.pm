package App::Netdisco::Util::Web;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';

use Time::Piece;
use Time::Seconds;
use HTML::Entities ();
use URI ();
use URI::QueryParam ();

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  sort_port sort_modules
  interval_to_daterange
  sql_match
  request_is_device
  request_is_api
  request_is_api_report
  request_is_api_search
  device_display_name
  page_title
  pane_chrome
  pane_history_header
  escape_for_script_context
  escape_results_token
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Web

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 request_is_device

Client has requested device content under C<.../device> or C<.../device/ports>.

=cut

sub request_is_device {
  return (
    index(request->path, uri_for('/device')->path) == 0
      or
    index(request->path, uri_for('/ajax/content/device/details')->path) == 0
      or
    index(request->path, uri_for('/ajax/content/device/ports')->path) == 0
  );
}

=head2 request_is_api

Client has requested JSON format data and an endpoint under C</api>.

=cut

sub request_is_api {
  # /api/ paths are always API endpoints regardless of Accept header
  return 1 if index(request->path, uri_for('/api/')->path) == 0;
  # for other paths, require Accept: json and a return_url pointing to /api/
  return ((request->accept and request->accept =~ m/(?:json|javascript)/)
    and param('return_url')
    and index(param('return_url'), uri_for('/api/')->path) == 0);
}

=head2 request_is_api_report

Same as C<request_is_api> but also requires path to start "C</api/v1/report/...>".

=cut

sub request_is_api_report {
  return (request_is_api and (
    index(request->path, uri_for('/api/v1/report/')->path) == 0
      or
    (param('return_url')
    and index(param('return_url'), uri_for('/api/v1/report/')->path) == 0)
  ));
}

=head2 request_is_api_search

Same as C<request_is_api> but also requires path to start "C</api/v1/search/...>".

=cut

sub request_is_api_search {
  return (request_is_api and (
    index(request->path, uri_for('/api/v1/search/')->path) == 0
      or
    (param('return_url')
    and index(param('return_url'), uri_for('/api/v1/search/')->path) == 0)
  ));
}

=head2 sql_match( $value, $exact? )

Convert wildcard characters "C<*>" and "C<?>" to "C<%>" and "C<_>"
respectively.

Pass a true value to C<$exact> to only substitute the existing wildcards, and
not also add "C<*>" to each end of the value.

In list context, returns two values, the translated value, and also an
L<SQL::Abstract> LIKE clause.

=cut

sub sql_match {
  my ($text, $exact) = @_;
  return unless $text;

  $text =~ s/^\s+//;
  $text =~ s/\s+$//;

  $text =~ s/[*]+/%/g;
  $text =~ s/[?]/_/g;

  $text = '%'. $text . '%' unless $exact;
  $text =~ s/\%+/%/g;

  return ( wantarray ? ($text, {-ilike => $text}) : $text );
}

=head2 sort_port( $a, $b )

Sort port names of various types used by device vendors. Interface is as
Perl's own C<sort> - two input args and an integer return value.

=cut

sub sort_port {
    my ($aval, $bval) = @_;

    # hack for foundry "10GigabitEthernet" -> cisco-like "TenGigabitEthernet"
    $aval = $1 if $aval =~ qr/^10(GigabitEthernet.+)$/;
    $bval = $1 if $bval =~ qr/^10(GigabitEthernet.+)$/;

    my $numbers        = qr{^(\d+)$};
    my $numeric        = qr{^([\d\.]+)$};
    my $dotted_numeric = qr{^(\d+)[:.](\d+)$};
    my $letter_number  = qr{^([a-zA-Z]+)(\d+)$};
    my $wordcharword   = qr{^([^:\/.]+)[-\ :\/\.]+([^:\/.0-9]+)(\d+)?$}; #port-channel45
    my $netgear        = qr{^Slot: (\d+) Port: (\d+) }; # "Slot: 0 Port: 15 Gigabit - Level"
    my $ciscofast      = qr{^
                            # Word Number slash (Gigabit0/)
                            (\D+)(\d+)[\/:]
                            # Groups of symbol float (/5.5/5.5/5.5), separated by slash or colon
                            ([\/:\.\d]+)
                            # Optional dash (-Bearer Channel)
                            (-.*)?
                            $}x;

    my @a = (); my @b = ();

    if ($aval =~ $dotted_numeric) {
        @a = ($1,$2);
    } elsif ($aval =~ $letter_number) {
        @a = ($1,$2);
    } elsif ($aval =~ $netgear) {
        @a = ($1,$2);
    } elsif ($aval =~ $numbers) {
        @a = ($1);
    } elsif ($aval =~ $ciscofast) {
        @a = ($1,$2);
        push @a, split(/[:\/]/,$3);
        push @a, $4 if defined $4;
    } elsif ($aval =~ $wordcharword) {
        @a = ($1,$2,$3);
    } else {
        @a = ($aval);
    }

    if ($bval =~ $dotted_numeric) {
        @b = ($1,$2);
    } elsif ($bval =~ $letter_number) {
        @b = ($1,$2);
    } elsif ($bval =~ $netgear) {
        @b = ($1,$2);
    } elsif ($bval =~ $numbers) {
        @b = ($1);
    } elsif ($bval =~ $ciscofast) {
        @b = ($1,$2);
        push @b, split(/[:\/]/,$3);
        push @b, $4 if defined $4;
    } elsif ($bval =~ $wordcharword) {
        @b = ($1,$2,$3);
    } else {
        @b = ($bval);
    }

    # Equal until proven otherwise
    my $val = 0;
    while (scalar(@a) or scalar(@b)){
        # carried around from the last find.
        last if $val != 0;

        my $a1 = shift @a;
        my $b1 = shift @b;

        # A has more components - loses
        unless (defined $b1){
            $val = 1;
            last;
        }

        # A has less components - wins
        unless (defined $a1) {
            $val = -1;
            last;
        }

        if ($a1 =~ $numeric and $b1 =~ $numeric){
            $val = $a1 <=> $b1;
        } elsif ($a1 ne $b1) {
            $val = $a1 cmp $b1;
        }
    }

    return $val;
}

=head2 sort_modules( $modules )

Sort devices modules into tree hierarchy based upon position and parent -
input arg is module list.

=cut

sub sort_modules {
    my $input = shift;
    my %modules;

    foreach my $module (@$input) {
        $modules{$module->index}{module} = $module;
        if ($module->parent) {
            # Example
            # index |              description               |        type         | parent |  class  | pos 
            #-------+----------------------------------------+---------------------+--------+---------+-----
            #     1 | Cisco Aironet 1200 Series Access Point | cevChassisAIRAP1210 |      0 | chassis |  -1
            #     3 | PowerPC405GP Ethernet                  | cevPortFEIP         |      1 | port    |  -1
            #     2 | 802.11G Radio                          | cevPortUnknown      |      1 | port    |   0

            # Some devices do not implement correctly, so given parent
            # can have multiple items within the same class at a single pos
            # value.  However, the database results are sorted by 1) parent
            # 2) class 3) pos 4) index so we should just be able to push onto
            # the array and ordering be preserved.
            {
              no warnings 'uninitialized';
              push(@{$modules{$module->parent}{children}{$module->class}}, $module->index);
            }
        } else {
            push(@{$modules{root}}, $module->index);
        }
    }
    return \%modules;
}

=head2 interval_to_daterange( $interval )

Takes an interval in days, weeks, months, or years in a format like '7 days'
and returns a date range in the format 'YYYY-MM-DD to YYYY-MM-DD' by
subtracting the interval from the current date.

If C<$interval> is not passed, epoch zero (1970-01-01) is used as the start.

=cut

sub interval_to_daterange {
    my $interval = shift;

    unless ($interval
        and $interval =~ m/^(?:\d+)\s+(?:day|week|month|year)s?$/) {

        return "1970-01-01 to " . Time::Piece->new->ymd;
    }

    my %const = (
        day   => ONE_DAY,
        week  => ONE_WEEK,
        month => ONE_MONTH,
        year  => ONE_YEAR
    );

    my ( $amt, $factor )
        = $interval =~ /^(\d+)\s+(day|week|month|year)s?$/gmx;

    $amt-- if $factor eq 'day';

    my $start = Time::Piece->new - $const{$factor} * $amt;

    return $start->ymd . " to " . Time::Piece->new->ymd;
}

=head2 device_display_name( $device )

The name shown for a Device row in the web interface: its DNS name, or its IP
when another device answers to the same DNS name.

=cut

sub device_display_name {
  my $device = shift or return undef;

  my $others = schema(vars->{'tenant'})->resultset('Device')
    ->search({ dns => $device->dns })->count() - 1;

  return ($others ? $device->ip : ($device->dns || $device->ip));
}

=head2 page_title( $page, $tab )

The browser title for the C<$tab> pane of C<$page>, where C<$page> is one of
C<device>, C<search>, C<report> or C<admin>.

Returns undef where the interface has no title for the tab, so that a caller
emitting this into a response leaves the current title alone rather than
replacing it with something wrong.

=cut

sub page_title {
  my ($page, $tab) = @_;
  $tab ||= '';

  if ($page eq 'device') {
    # before the device lookup, so an unknown tag costs no query
    my $config = _tab_config('device', $tab) or return undef;
    my $device = _device_for_query( param('q') ) or return undef;
    return device_display_name($device) .' - '. $config->{'label'};
  }

  # the port log is the one report naming its subject beside the tab
  my $report = (($page eq 'report' and $tab eq 'portlog')
    ? setting('_reports')->{ $tab } : undef);

  if ($report) {
    return _one_line(join ' ', (param('q') || ''), '-', (param('f') || ''))
      .' - '. $report->{'label'};
  }

  return setting('branding_text');
}

# the registry entry a web plugin made for this tab, or undef when nothing
# registered the name. Reports and admin tasks are keyed by tag; device and
# search tabs are an ordered list, because the page renders them in that order.
sub _tab_config {
  my ($page, $tab) = @_;
  return undef unless defined $tab and length $tab;

  return setting('_reports')->{ $tab }     if $page eq 'report';
  return setting('_admin_tasks')->{ $tab } if $page eq 'admin';

  foreach my $item (@{ setting("_${page}_tabs") || [] }) {
    return $item if $item->{'tag'} eq $tab;
  }
  return undef;
}

sub _device_for_query {
  my $q = shift or return undef;

  # the same lookup the /device page makes, so that the title matches the name
  # that page rendered, which is what the browser reads today
  return schema(vars->{'tenant'})->resultset('Device')->search({
    -or => [
      \[ 'host(me.ip) = ?' => [ bind_value => $q ] ],
      'me.dns' => $q,
    ],
  })->first;
}

# report.tt lays the port log's parts out over several lines, which the
# browser would otherwise carry into the tab
sub _one_line {
  my $text = shift;
  $text = '' unless defined $text;

  $text =~ s/\s+/ /g;
  $text =~ s/^\s+|\s+$//g;
  return $text;
}

=head2 pane_history_header( $page, $tab )

The C<HX-Push-Url> or C<HX-Replace-Url> header for the C<$tab> pane of
C<$page>, as a name and value pair for L<Dancer::Response/header>. htmx puts
the value in the address bar, and reads the value C<false> as an instruction
to leave the history alone.

The value is the address of the page the pane belongs to, carrying the query
the sidebar form submitted, so that opening it fresh renders the same tab with
the same results.

=cut

sub pane_history_header {
  my ($page, $tab) = @_;

  # an admin task has never had an address of its own for its options, and the
  # job queue refetches on a timer, which would be a history entry every few
  # seconds. "false" rather than no header at all, because htmx reads the
  # header before any hx-push-url attribute and nothing else can overrule one.
  return ('HX-Push-Url' => 'false') if $page eq 'admin';

  # the query the form serialized, rather than the my_query token, which
  # stringifies a repeated parameter as an array reference
  my $query = request->env->{'QUERY_STRING'} || '';
  my $path  = uri_for(($page eq 'report') ? "/report/$tab" : "/$page")->path;
  my $url   = $path . (length $query ? ('?'. $query) : '');

  my $leaving = _htmx_current_url();

  if ($page eq 'report') {
      # a report with no options submits an empty query, and repeating the
      # address it is already showing would be an entry that the Back button
      # appears to ignore
      return ('HX-Push-Url' => 'false')
        if (not length $query) and $leaving and $leaving->path eq $path;

      return ('HX-Push-Url' => $url);
  }

  # a device or search tab change is a new page in the history but a change to
  # the options of the tab already shown is not, which here is the difference
  # between the tab asked for and the tab of the page htmx is leaving
  my $leaving_tab = $leaving ? $leaving->query_param('tab') : undef;

  return ('HX-Push-Url' => $url)
    if defined $leaving_tab and $leaving_tab ne $tab;

  return ('HX-Replace-Url' => $url);
}

# htmx sends the address bar contents with every request it makes
sub _htmx_current_url {
  my $current = request->env->{'HTTP_HX_CURRENT_URL'} or return undef;
  return URI->new($current);
}

=head2 pane_chrome( $page, $tab )

The chrome around the C<$tab> pane of C<$page> that changes with the tab: the
CSV download link, and on the device page the sidebar reset link. Returned as
C<hx-swap-oob> markup for the same response that carries the pane, so that one
answer paints the pane and everything around it.

Returns the empty string where the page shell carries neither, which is also
what an unregistered tag gets. That is not tidiness: htmx drops an out-of-band
element naming an id the page does not have, and says nothing at all about it,
so C<netdisco.js> reports the shortfall as a script error.

The sidebar itself is deliberately absent. Whether a tab has one is declared by
the sidebar templates, both by which of them exist on an include path that
site-local plugins extend and by two of them reporting that they carry only
hidden fields, so no route can answer it without duplicating template text.

=cut

sub pane_chrome {
  my ($page, $tab) = @_;
  my $config = _tab_config($page, $tab) or return '';

  return join '', _csv_download_link($page, $tab, $config),
                  _sidebar_reset_link($page, $tab);
}

# The device and search shells render the anchor for every tab and show or hide
# it per tab; the report and admin shells render it only where the tab offers a
# download, and give the job queue and the port log a different set of controls
# in the same corner.
sub _csv_download_link {
  my ($page, $tab, $config) = @_;

  if ($page eq 'report' or $page eq 'admin') {
    return '' unless $config->{'provides_csv'};
    return '' if $tab eq 'portlog' or $tab eq 'jobqueue';
  }

  my $query = request->env->{'QUERY_STRING'} || '';
  my $href = uri_for("/ajax/content/$page/$tab")->path
    . (length $query ? ('?'. $query) : '');

  return _oob_anchor('nd_csv-download', $href,
    ($config->{'provides_csv'} ? '' : ' hidden'),
    ' download="'. _escape_attr("netdisco-$page-$tab.csv") .'"',
    '<i id="nd_csv-download-icon" class="text-info far fa-file-lines fa-lg"'
    .' rel="tooltip" data-bs-placement="left" data-bs-title="Download as CSV"></i>');
}

# the fields each device tab offers, in the order the sidebar renders them, so
# that the reset address reads the way it did when the browser built it
my %RESET_FIELDS = (
  ports  => [qw/q f partial invert/],
  netmap => [qw/q/],
);

# only the device page has a reset anchor, and only for the two tabs whose
# sidebar has anything to reset. Nothing is emitted for the others, which is
# what the shell does today: the anchor keeps the address it last had, behind a
# sidebar those tabs hide anyway.
sub _sidebar_reset_link {
  my ($page, $tab) = @_;
  return '' unless $page eq 'device';

  my $fields = $RESET_FIELDS{ $tab } or return '';

  my $uri = URI->new( uri_for('/device')->path );
  $uri->query_form(tab => $tab, reset => 'on', firstsearch => 'on',
    map  {; ($_ => scalar param($_)) }
    grep {; defined scalar param($_) } @$fields);

  return _oob_anchor('nd_sidebar-reset-link', $uri->as_string, '', '',
    '<i class="nd_sidebar-reset fas fa-arrow-rotate-left"'
    .' rel="tooltip" data-bs-placement="left" data-bs-title="Reset to Defaults"'
    .' data-bs-container="body"></i>');
}

sub _oob_anchor {
  my ($id, $href, $hidden, $extra, $content) = @_;

  return '<a id="'. $id .'" hx-swap-oob="true"'. $hidden
    .' href="'. _escape_attr($href) .'"'. $extra .'>'. $content .'</a>';
}

sub _escape_attr {
  return HTML::Entities::encode_entities(shift, q{<>&"'});
}

=head2 escape_for_script_context( $json )

Makes a JSON string safe to embed as a JavaScript literal inside an HTML
C<< <script> >> element, which is how the report and search templates ship
their result sets. Returns anything that is not a defined plain scalar
unchanged, so a resultset or an arrayref passed to a CSV or API template is
left alone.

=cut

sub escape_for_script_context {
  my $json = shift;
  return $json if (not defined $json) or ref $json;

  # Inside a script element the HTML parser ends the element at "</" and
  # changes state at "<!--" and "<script", none of which it stops doing just
  # because the sequence sits inside a JavaScript string. Escaping every "<"
  # covers all three. Both JSON.parse and the JavaScript parser read the
  # escape back as "<", so the data the page receives is unchanged.
  $json =~ s/</\\u003C/g;

  # Not an HTML concern. This JSON is emitted as JavaScript source rather than
  # parsed from a string, and these two characters are line terminators there.
  $json =~ s/\x{2028}/\\u2028/g;
  $json =~ s/\x{2029}/\\u2029/g;

  return $json;
}

=head2 escape_results_token( $tokens )

Applies C<escape_for_script_context> to the C<results> token of a template
token hash, in place, and returns the hash.

Only when the key is already there. The API serializer chooses between
emitting C<results> alone and walking the whole token hash on C<exists
$tokens-E<gt>{results}>, and a handler that renders without that token, as
node search does, needs the second. Assigning unconditionally would
autovivify the key and silently move such a handler onto the first branch.

=cut

sub escape_results_token {
  my $tokens = shift;
  return $tokens unless (ref {} eq ref $tokens) and exists $tokens->{results};

  $tokens->{results} = escape_for_script_context( $tokens->{results} );
  return $tokens;
}

1;
