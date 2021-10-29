use utf8;
package App::Netdisco::DB::Result::Virtual::OidChildren;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table("oid_children");
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL

    WITH params AS (SELECT ?::inet AS ip, ?::int[] AS root),
           args AS (SELECT array_length(params.root,1) AS rootlen FROM params)
    SELECT DISTINCT(oid_parts[(args.rootlen + 1)]) AS part,
           (SELECT count(DISTINCT(db2.oid_parts[1:(args.rootlen + 2)])) FROM device_browser db2
                            WHERE db2.oid_parts[1:(args.rootlen + 1)] = device_browser.oid_parts[1:(args.rootlen + 1)]
                            AND db2.ip = params.ip) AS children
      FROM device_browser, params, args
      WHERE device_browser.ip = params.ip
      AND device_browser.oid_parts[1:(args.rootlen)] = params.root
      ORDER BY part

ENDSQL
);

__PACKAGE__->add_columns(
  'part'     => { data_type => 'integer' },
  'children' => { data_type => 'integer' },
);

1;
