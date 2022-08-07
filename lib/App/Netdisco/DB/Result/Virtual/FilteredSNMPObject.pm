use utf8;
package App::Netdisco::DB::Result::Virtual::FilteredSNMPObject;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table("filtered_snmp_object");
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL

    SELECT so.oid, so.oid_parts, so.mib, so.leaf, so.type, so.access, so.index, so.status, so.enum, so.descr, so.num_children,
           count(db.oid) AS browser
      FROM snmp_object so

      LEFT JOIN device_browser db ON
           (db.ip = ? AND
            ((so.oid = db.oid)
              OR (array_length(db.oid_parts,1) > ?
                  AND db.oid LIKE so.oid || '.%')))

      WHERE array_length(so.oid_parts,1) = ?
            AND so.oid LIKE ?::text || '.%'

      GROUP BY so.oid, so.oid_parts, so.mib, so.leaf, so.type, so.access, so.index, so.status, so.enum, so.descr, so.num_children

ENDSQL
);

__PACKAGE__->add_columns(
  'oid'    => { data_type => 'text' },
  'oid_parts' => { data_type => 'integer[]' },
  'mib'    => { data_type => 'text' },
  'leaf'   => { data_type => 'text' },
  'type'   => { data_type => 'text' },
  'access' => { data_type => 'text' },
  'index'  => { data_type => 'text[]' },
  'status' => { data_type => 'text' },
  'enum'   => { data_type => 'text[]' },
  'descr'  => { data_type => 'text' },
  'num_children' => { data_type => 'integer' },
  'browser' => { data_type => 'integer' },
);

1;
