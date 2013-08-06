use utf8;
package App::Netdisco::DB::Result::Virtual::UserRole;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table("user_role");
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
  SELECT username, 'port_control' AS role FROM users
    WHERE port_control
  UNION
  SELECT username, 'admin' AS role FROM users
    WHERE admin
ENDSQL
);

__PACKAGE__->add_columns(
  'username' => { data_type => 'text' },
  'role' => { data_type => 'text' },
);

1;
