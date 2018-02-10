package App::Netdisco::DB::Result::Virtual::TastyJobs;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('tasty_jobs');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
  SELECT jobs.*, ds2.deferrals AS num_deferrals
    FROM (
      (SELECT me.*, 100 AS job_priority
         FROM admin me
        WHERE ( me.username IS NOT NULL OR me.action = ANY (string_to_array(btrim(?, '{"}'), '","')) )
          AND me.device NOT IN
              (SELECT ds.device
                 FROM device_skip ds
                WHERE ( me.action = ANY (ds.actionset) OR
                        (ds.deferrals >= ? AND ds.last_defer > ( LOCALTIMESTAMP - ?::interval )) )
                  AND ds.backend = ? AND ds.device = me.device)
          AND me.status = 'queued'
     ORDER BY random()
        LIMIT ?)
   UNION
      (SELECT me.*, 0 AS job_priority
         FROM admin me
        WHERE NOT (me.action = ANY (string_to_array(btrim(?, '{"}'), '","')))
          AND me.device NOT IN
              (SELECT ds.device
                 FROM device_skip ds
                WHERE ( me.action = ANY (ds.actionset) OR
                        (ds.deferrals >= ? AND ds.last_defer > ( LOCALTIMESTAMP - ?::interval )) )
                  AND ds.backend = ? AND ds.device = me.device)
          AND me.status = 'queued'
     ORDER BY random()
        LIMIT ?)
    ) jobs
    LEFT OUTER JOIN device_skip ds2
      ON ds2.backend = ? AND ds2.device = jobs.device
   ORDER BY jobs.job_priority DESC,
            ds2.deferrals ASC NULLS FIRST
   LIMIT ?
ENDSQL
);

__PACKAGE__->add_columns(
  "job",
  { data_type => "integer", is_nullable => 0, },
  "entered",
  { data_type => "timestamp", is_nullable => 1 },
  "started",
  { data_type => "timestamp", is_nullable => 1 },
  "finished",
  { data_type => "timestamp", is_nullable => 1 },
  "device",
  { data_type => "inet", is_nullable => 1 },
  "port",
  { data_type => "text", is_nullable => 1 },
  "action",
  { data_type => "text", is_nullable => 1 },
  "subaction",
  { data_type => "text", is_nullable => 1 },
  "status",
  { data_type => "text", is_nullable => 1 },
  "username",
  { data_type => "text", is_nullable => 1 },
  "userip",
  { data_type => "inet", is_nullable => 1 },
  "log",
  { data_type => "text", is_nullable => 1 },
  "debug",
  { data_type => "boolean", is_nullable => 1 },
  "device_key",
  { data_type => "text", is_nullable => 1 },
  "job_priority",
  { data_type => "integer", is_nullable => 1 },
  "num_deferrals",
  { data_type => "integer", is_nullable => 1 },
);

__PACKAGE__->set_primary_key("job");

1;
