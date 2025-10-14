use utf8;
package App::Netdisco::DB::Result::User;


use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("users");
__PACKAGE__->add_columns(
  "username",
  { data_type => "varchar", is_nullable => 0, size => 50 },
  "password",
  { data_type => "text", is_nullable => 1 },
  "token",
  { data_type => "text", is_nullable => 1 },
  "token_from",
  { data_type => "integer", is_nullable => 1 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
  "last_on",
  { data_type => "timestamp", is_nullable => 1 },
  "port_control",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "portctl_role",
  { data_type => "text", is_nullable => 1 },
  "portctl_checkpoint",
  { data_type => "integer", default_value => '1', is_nullable => 0 },
  "ldap",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "radius",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "tacacs",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "admin",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "fullname",
  { data_type => "text", is_nullable => 1 },
  "note",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("username");

__PACKAGE__->has_many( roles => 'App::Netdisco::DB::Result::Virtual::UserRole',
  'username', { cascade_copy => 0, cascade_update => 0, cascade_delete => 0 } );

sub created   { return (shift)->get_column('created')  }
sub last_seen { return (shift)->get_column('last_seen')  }

1;
