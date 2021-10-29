use utf8;
package App::Netdisco::DB::Result::Virtual::FilteredSNMPObject;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table("filtered_snmp_object");
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL

    SELECT oid, oid_parts, mib, leaf, type, access, index
      FROM snmp_object
      WHERE oid LIKE ?::text || '.%'
        AND oid_parts[?] = ANY (?)
        AND array_length(oid_parts,1) = ?

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
);

1;
