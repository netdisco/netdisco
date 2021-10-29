use utf8;
package App::Netdisco::DB::Result::Virtual::OidChildren;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table("oid_children");
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL

    SELECT DISTINCT(db.oid_parts[?]) AS part, count(distinct(db2.oid_parts[?])) as children
      FROM device_browser db

      LEFT JOIN device_browser db2
      ON (db2.oid LIKE ? || '.%'
          AND db2.oid_parts[?] = db.oid_parts[?]
          AND db2.ip = db.ip)

      WHERE db.ip = ?
            AND db.oid LIKE ? || '.%'

      GROUP BY db.oid_parts

ENDSQL
);

__PACKAGE__->add_columns(
  'part'     => { data_type => 'integer' },
  'children' => { data_type => 'integer' },
);

1;
