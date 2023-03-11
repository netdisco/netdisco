package App::Netdisco::DB::Result::Virtual::WalkJobs;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('walk_jobs');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
    SELECT ip
    FROM device

    LEFT OUTER JOIN admin ON (device.ip = admin.device
                              AND admin.status = 'queued'
                              AND admin.action = ?)

    FULL OUTER JOIN device_skip ON (device_skip.device = device.ip
                                    AND (device_skip.actionset @> string_to_array(?, '')
                                         OR (device_skip.deferrals >= ?
                                             AND device_skip.last_defer > (LOCALTIMESTAMP - ? ::interval))))

    WHERE admin.device IS NULL
      AND device.ip IS NOT NULL

    GROUP BY device.ip
    HAVING count(device_skip.backend) < (SELECT count(distinct(backend)) FROM device_skip)

    ORDER BY device.ip ASC
ENDSQL
);

__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
);

__PACKAGE__->set_primary_key("ip");

1;
