package App::Netdisco::Util::Web;

use strict;
use warnings;

use Dancer ':syntax';

use Time::Piece;
use Time::Seconds;

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
  return ((request->accept and request->accept =~ m/(?:json|javascript)/) and (
    index(request->path, uri_for('/api/')->path) == 0
      or
    (param('return_url')
    and index(param('return_url'), uri_for('/api/')->path) == 0)
  ));
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
        push @a, split(/[:\/]/,$3), $4;
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
        push @b, split(/[:\/]/,$3),$4;
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

1;
