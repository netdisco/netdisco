package App::Netdisco::DB::Result::Virtual::SlowDevices;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('slow_devices');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
  SELECT a.action, a.device, a.started, a.finished,
      justify_interval(extract(epoch FROM (a.finished - a.started)) * interval '1 second') AS elapsed
    FROM admin a
    INNER JOIN (
      SELECT device, action, max(started) AS started
      FROM admin
      WHERE status = 'done'
        AND action IN ('discover','macsuck','arpnip')
      GROUP BY action, device
    ) b
    ON a.device = b.device AND a.started = b.started
    ORDER BY elapsed desc, action, device
    LIMIT 20
ENDSQL
);

__PACKAGE__->add_columns(
  "action",
  { data_type => "text", is_nullable => 1 },
  "device",
  { data_type => "inet", is_nullable => 1 },
  "started",
  { data_type => "timestamp", is_nullable => 1 },
  "finished",
  { data_type => "timestamp", is_nullable => 1 },
  "elapsed",
  { data_type => "interval", is_nullable => 1 },
);

1;
