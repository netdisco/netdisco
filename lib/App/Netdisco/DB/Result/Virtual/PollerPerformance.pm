package App::Netdisco::DB::Result::Virtual::PollerPerformance;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('poller_performance');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
  SELECT action,
         entered,
         to_char( entered, 'YYYY-MM-DD HH24:MI:SS' ) AS entered_stamp,
         COUNT( device ) AS number,
         MIN( started ) AS start,
         MAX( finished ) AS end,
         justify_interval(
           extract ( epoch FROM( max( finished ) - min( started ) ) )
             * interval '1 second'
         ) AS elapsed
    FROM admin
    WHERE action IN ( 'discover', 'macsuck', 'arpnip', 'nbtstat' ) 
    GROUP BY action, entered 
    HAVING count( device ) > 1
      AND SUM( CASE WHEN status LIKE 'queued%' THEN 1 ELSE 0 END ) = 0
    ORDER BY entered DESC, elapsed DESC
    LIMIT 30
ENDSQL
);

__PACKAGE__->add_columns(
  "action",
  { data_type => "text", is_nullable => 1 },
  "entered",
  { data_type => "timestamp", is_nullable => 1 },
  "entered_stamp",
  { data_type => "text", is_nullable => 1 },
  "number",
  { data_type => "integer", is_nullable => 1 },
  "start",
  { data_type => "timestamp", is_nullable => 1 },
  "end",
  { data_type => "timestamp", is_nullable => 1 },
  "elapsed",
  { data_type => "interval", is_nullable => 1 },
);

1;
