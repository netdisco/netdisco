use utf8;
package App::Netdisco::DB::Result::User;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("users");
__PACKAGE__->add_columns(
  "username",
  { data_type => "varchar", is_nullable => 0, size => 50 },
  "password",
  { data_type => "text", is_nullable => 1 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
  "last_on",
  { data_type => "timestamp", is_nullable => 1 },
  "port_control",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "ldap",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "admin",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "fullname",
  { data_type => "text", is_nullable => 1 },
  "note",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("username");


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:2awpSJkzXP7+8eyT4vGjfw

__PACKAGE__->has_many( roles => 'App::Netdisco::DB::Result::Virtual::UserRole',
  'username', { cascade_copy => 0, cascade_update => 0, cascade_delete => 0 } );

# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
