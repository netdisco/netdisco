use utf8;
package App::Netdisco::DB::Result::Virtual::OidChildren;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table("oid_children");
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL

    SELECT DISTINCT(oid_parts[?]) AS part,
           (SELECT count(DISTINCT(db2.oid_parts[1:?])) FROM device_browser db2
                            WHERE db2.oid_parts[1:?] = device_browser.oid_parts[1:?]
                            AND db2.ip = ?) AS children
      FROM device_browser
      WHERE device_browser.ip = ?
      AND device_browser.oid LIKE ?::text || '.%'

ENDSQL
);

__PACKAGE__->add_columns(
  'part'     => { data_type => 'integer' },
  'children' => { data_type => 'integer' },
);

1;
