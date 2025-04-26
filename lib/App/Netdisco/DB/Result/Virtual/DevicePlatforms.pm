package App::Netdisco::DB::Result::Virtual::DevicePlatforms;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('device_platforms');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
  SELECT device.vendor, device.model,
    CASE WHEN count(distinct( module.serial )) = 0
      THEN count(distinct( device.ip ))
      ELSE count(distinct( module.serial )) END
      AS count
  FROM device
    LEFT JOIN device_module module
      ON (device.ip = module.ip and module.class = 'chassis'
        AND module.serial IS NOT NULL
        AND module.serial != '')
  GROUP BY device.vendor, device.model
ENDSQL
);

__PACKAGE__->add_columns(
  'vendor' => {
    data_type => 'text',
  },
  'model' => {
    data_type => 'text',
  },
  'count' => {
    data_type => 'integer',
  },
);

1;
