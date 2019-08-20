use utf8;
package App::Netdisco::DB::Result::DevicePortLog;


use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("device_port_log");
__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "device_port_log_id_seq",
  },
  "ip",
  { data_type => "inet", is_nullable => 1 },
  "port",
  { data_type => "text", is_nullable => 1 },
  "reason",
  { data_type => "text", is_nullable => 1 },
  "log",
  { data_type => "text", is_nullable => 1 },
  "username",
  { data_type => "text", is_nullable => 1 },
  "userip",
  { data_type => "inet", is_nullable => 1 },
  "action",
  { data_type => "text", is_nullable => 1 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
);

__PACKAGE__->set_primary_key("id");

=head1 ADDITIONAL COLUMNS

=head2 creation_stamp
 
Formatted version of the C<creation> field, accurate to the second.
 
The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:
 
 2012-02-06 12:49:23
 
=cut
 
sub creation_stamp  { return (shift)->get_column('creation_stamp')  }

1;
