use utf8;
package App::Netdisco::DB::Result::Virtual::OidChildren;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table("oid_children");
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
    SELECT
        DISTINCT(split_part(oid,'.',?))::int AS part,
        (SELECT count (*) FROM device_browser db2 WHERE db2.oid LIKE (? || '.' || split_part(db.oid,'.',?) || '.%') AND ip = ?) AS children
      FROM device_browser db
      WHERE ip = ?
      AND oid LIKE (? || '.%')
      ORDER BY part
ENDSQL
);

__PACKAGE__->add_columns(
  'part'     => { data_type => 'integer' },
  'children' => { data_type => 'integer' },
);

1;
