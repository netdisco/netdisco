package App::Netdisco::DB::Result::Virtual::TastyJobs;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('tasty_jobs');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
  WITH my_jobs AS
    (SELECT admin.* FROM admin
       LEFT OUTER JOIN device_skip ds
         ON (ds.backend = ? AND admin.device = ds.device
             AND admin.action = ANY (ds.actionset))
      WHERE admin.status = 'queued'
        AND admin.backend IS NULL
        AND ds.device IS NULL)

  SELECT my_jobs.*,
         CASE WHEN ( (my_jobs.username IS NOT NULL AND (((ds.deferrals = 0 OR ds.deferrals IS NULL) AND ds.last_defer IS NULL)
                                                        OR my_jobs.entered > ds.last_defer))
                    OR (my_jobs.action = ANY (string_to_array(btrim(?, '{"}'), '","'))) )
              THEN 100
              ELSE 0
          END AS job_priority
    FROM my_jobs

    LEFT OUTER JOIN device_skip ds
      ON (ds.backend = ? AND ds.device = my_jobs.device)

   WHERE ds.deferrals < ?
      OR (my_jobs.username IS NOT NULL AND (ds.last_defer IS NULL
                                            OR my_jobs.entered > ds.last_defer))
      OR (ds.deferrals IS NULL AND ds.last_defer IS NULL)
      OR ds.last_defer <= ( LOCALTIMESTAMP - ?::interval )

   ORDER BY job_priority DESC,
            ds.deferrals ASC NULLS FIRST,
            ds.last_defer ASC NULLS LAST,
            device_key DESC NULLS LAST,
            random()
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
);

__PACKAGE__->set_primary_key("job");

1;
