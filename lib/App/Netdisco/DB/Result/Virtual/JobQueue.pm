package App::Netdisco::DB::Result::Virtual::JobQueue;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('job_queue');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
  WITH limited_jobs AS
    (SELECT a.job, max(ds.deferrals) AS max_defer, min(ds.last_defer) AS min_defer,
            CASE WHEN a.status = 'queued' THEN 100
                 WHEN a.status LIKE 'queued-%' THEN 80
                 WHEN a.status = 'error' THEN 60
                 ELSE 40
             END AS status_priority,
            CASE WHEN (a.username IS NOT NULL OR
                       a.action = ANY (string_to_array(btrim(?, '{"}'), '","')))
                 THEN 100
                 ELSE 0
             END AS job_priority
       FROM admin a LEFT OUTER JOIN device_skip ds USING (device)
      WHERE (?::text is NULL or a.device <<= ?)
   GROUP BY a.job
   ORDER BY status_priority DESC,
            job_priority DESC,
            max_defer ASC NULLS FIRST,
            min_defer ASC NULLS LAST,
            a.device, a.action)

  SELECT to_char( entered, 'YYYY-MM-DD HH24:MI' ) AS entered_stamp,
         username, action, device, subaction, port, status, log,
         replace( age( finished, started ) ::text, 'mon', 'month' ) AS duration,
         array(SELECT ('backend',backend,'actionset',actionset,'deferrals',deferrals,'last_defer',EXTRACT(EPOCH FROM last_defer))
                 FROM device_skip ds
                WHERE ds.device = a.device) AS skips

    FROM admin a INNER JOIN limited_jobs jobs USING (job)
ENDSQL
);

__PACKAGE__->add_columns(
  "device",
  { data_type => "inet", is_nullable => 0 },
  "action",
  { data_type => "text", is_nullable => 1 },
  "subaction",
  { data_type => "text", is_nullable => 1 },
  "port",
  { data_type => "text", is_nullable => 1 },
  "status",
  { data_type => "text", is_nullable => 1 },
  "username",
  { data_type => "text", is_nullable => 1 },
  "log",
  { data_type => "text", is_nullable => 1 },

  "skips",
  { data_type => "[text]", is_nullable => 1 },

  "entered_stamp",
  { data_type => "text", is_nullable => 1 },
  "duration",
  { data_type => "text", is_nullable => 1 },
);

__PACKAGE__->belongs_to('target', 'App::Netdisco::DB::Result::Device',
  { 'foreign.ip' => 'self.device' }, { join_type => 'LEFT' } );

1;
