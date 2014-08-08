use utf8;
package App::Netdisco::DB::Result::Admin;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("admin");
__PACKAGE__->add_columns(
  "job",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "admin_job_seq",
  },
  "entered",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
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


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:gW4JW4pMgrufFIxFeYPYpw

__PACKAGE__->set_primary_key("job");

# You can replace this text with custom code or comments, and it will be preserved on regeneration

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

=head2 entererd_stamp

Formatted version of the C<entered> field, accurate to the minute.

The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:

 2012-02-06 12:49

=cut

sub entered_stamp  { return (shift)->get_column('entered_stamp')  }

=head2 started_stamp

Formatted version of the C<started> field, accurate to the minute.

The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:

 2012-02-06 12:49

=cut

sub started_stamp  { return (shift)->get_column('started_stamp')  }

=head2 finished_stamp

Formatted version of the C<finished> field, accurate to the minute.

The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:

 2012-02-06 12:49

=cut

sub finished_stamp  { return (shift)->get_column('finished_stamp')  }

1;
