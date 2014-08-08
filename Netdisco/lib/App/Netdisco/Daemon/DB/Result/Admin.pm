use utf8;
package App::Netdisco::Daemon::DB::Result::Admin;

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("admin");
__PACKAGE__->add_columns(
  "job",
  { data_type => "integer", is_nullable => 0 },

  "type", # Poller, Interactive, etc
  { data_type => "text", is_nullable => 0 },

  "wid", # worker ID, only != 0 once taken
  { data_type => "integer", is_nullable => 0, default_value => 0 },

  "entered",
  { data_type => "timestamp", is_nullable => 1 },
  "started",
  { data_type => "timestamp", is_nullable => 1 },
  "finished",
  { data_type => "timestamp", is_nullable => 1 },
  "device",
  { data_type => "inet", is_nullable => 1 },
  "port",
  { data_type => "text", is_nullable => 1 },
  "action",
  { data_type => "text", is_nullable => 1 },
  "subaction",
  { data_type => "text", is_nullable => 1 },
  "status",
  { data_type => "text", is_nullable => 1 },
  "username",
  { data_type => "text", is_nullable => 1 },
  "userip",
  { data_type => "inet", is_nullable => 1 },
  "log",
  { data_type => "text", is_nullable => 1 },
  "debug",
  { data_type => "boolean", is_nullable => 1 },
);

__PACKAGE__->set_primary_key("job");

=head1 METHODS

=head2 summary

An attempt to make a meaningful statement about the job.

=cut

sub summary {
    my $job = shift;
    return join ' ',
      $job->action,
      ($job->device || ''),
      ($job->port || '');
#      ($job->subaction ? (q{'}. $job->subaction .q{'}) : '');
}

=head1 ADDITIONAL COLUMNS

=head2 extra

Alias for the C<subaction> column.

=cut

sub extra { (shift)->subaction }

=head2 entererd_stamp

Formatted version of the C<entered> field, accurate to the minute.

The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:

 2012-02-06 12:49

=cut

sub entered_stamp {
  (my $stamp = (shift)->entered) =~ s/\.\d+$//;
  return $stamp;
}

1;
