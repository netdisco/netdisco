use utf8;
package App::Netdisco::DB::Result::Admin;


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
  "device_key",
  { data_type => "text", is_nullable => 1 },
);



__PACKAGE__->set_primary_key("job");

# You can replace this text with custom code or comments, and it will be preserved on regeneration

=head1 RELATIONSHIPS

=head2 device_skips( $backend?, $max_deferrals?, $retry_after? )

Returns the set of C<device_skip> entries which apply to this job. They match
the device IP, current backend, and job action.

You probably want to use the ResultSet method C<skipped> which completes this
query with a C<backend> host, C<max_deferrals>, and C<retry_after> parameters
(or sensible defaults).

=cut

__PACKAGE__->might_have( device_skips => 'App::Netdisco::DB::Result::DeviceSkip',
  sub {
    my $args = shift;
    return {
      "$args->{foreign_alias}.backend" => { '=' => \'?' },
      "$args->{foreign_alias}.device"
        => { -ident => "$args->{self_alias}.device" },
      -or => [
        "$args->{foreign_alias}.actionset"
            => { '@>' => \"string_to_array($args->{self_alias}.action,'')" },
        -and => [
            "$args->{foreign_alias}.deferrals"  => { '>=' => \'?' },
            "$args->{foreign_alias}.last_defer" =>
                { '>', \'(LOCALTIMESTAMP - ?::interval)' },
        ],
      ],
    };
  },
  { cascade_copy => 0, cascade_update => 0, cascade_delete => 0 }
);

=head2 target

Returns the single C<device> to which this Job entry was associated.

The JOIN is of type LEFT, in case the C<device> is not in the database.

=cut

__PACKAGE__->belongs_to( target => 'App::Netdisco::DB::Result::Device',
  { 'foreign.ip' => 'self.device' }, { join_type => 'LEFT' } );

=head1 METHODS

=head2 display_name

An attempt to make a meaningful statement about the job.

=cut

sub display_name {
    my $job = shift;
    return join ' ',
      $job->action,
      ($job->device || ''),
      ($job->port || '');
#      ($job->subaction ? (q{'}. $job->subaction .q{'}) : '');
}

=head1 ADDITIONAL COLUMNS

=head2 entered_stamp

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
