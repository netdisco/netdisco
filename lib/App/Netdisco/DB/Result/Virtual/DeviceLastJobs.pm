package App::Netdisco::DB::Result::Virtual::DeviceLastJobs;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

# The most recent finished job per device and action, whatever its status:
# a failing macsuck is the case worth seeing, so this is not limited to done
# jobs as SlowDevices is.
__PACKAGE__->table('device_last_jobs');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
  SELECT DISTINCT ON (device, action)
      device, action, status,
      floor(extract(epoch FROM started)) AS started_epoch,
      extract(epoch FROM (finished - started)) AS duration
    FROM admin
    WHERE device IS NOT NULL
      AND started IS NOT NULL
      AND finished IS NOT NULL
    ORDER BY device, action, started DESC
ENDSQL
);

__PACKAGE__->add_columns(
  "device",
  { data_type => "inet", is_nullable => 1 },
  "action",
  { data_type => "text", is_nullable => 1 },
  "status",
  { data_type => "text", is_nullable => 1 },
  "started_epoch",
  { data_type => "bigint", is_nullable => 1 },
  "duration",
  { data_type => "numeric", is_nullable => 1 },
);

1;
