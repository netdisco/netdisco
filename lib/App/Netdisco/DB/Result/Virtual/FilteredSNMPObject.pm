use utf8;
package App::Netdisco::DB::Result::Virtual::FilteredSNMPObject;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table("filtered_snmp_object");
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL

    WITH params AS (SELECT ?::int[] AS root, ?::int[] AS children),
           args AS (SELECT array_length(params.root,1) AS rootlen FROM params)

    SELECT oid, mib, leaf, type, munge, access, index
      FROM snmp_object, params, args
      WHERE oid[1:(args.rootlen)] = params.root
        AND oid[(args.rootlen + 1)] = ANY (children)
        AND array_length(oid,1) = (args.rootlen + 1)
      ORDER BY oid

ENDSQL
);

__PACKAGE__->add_columns(
  'oid'    => { data_type => 'integer[]' },
  'mib'    => { data_type => 'text' },
  'leaf'   => { data_type => 'text' },
  'type'   => { data_type => 'text' },
  'munge'  => { data_type => 'text' },
  'access' => { data_type => 'text' },
  'index'  => { data_type => 'text[]' },
);

1;
