package App::Netdisco::DB::Result::Virtual::MLAGPeers;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table('mlag_peers');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
SELECT d1.dns AS dns,  dp1.ip AS ip,      dp1.port AS port,      dp1.slave_of AS lag,
       d2.dns AS mid,  dp2.ip AS mid_ip,  dp2.port AS mid_port,  dp2.slave_of AS mid_lag,
       d3.dns AS peer, dp5.ip AS peer_ip, dp5.port AS peer_port, dp6.port AS peer_lag
  FROM device_port dp1 LEFT JOIN device_port dp2
        ON dp1.remote_ip = dp2.ip
        AND dp1.remote_port = dp2.port
      LEFT JOIN device_port dp3
        ON dp2.ip = dp3.ip
        AND dp2.slave_of = dp3.port
      RIGHT JOIN device_port dp4
        ON dp4.remote_ip != dp1.ip
        AND dp3.ip = dp4.ip
        AND dp3.port = dp4.slave_of
      LEFT JOIN device_port dp5
        ON dp4.remote_ip = dp5.ip
        AND dp4.remote_port = dp5.port
      LEFT JOIN device_port dp6
        ON dp5.ip = dp6.ip
        AND dp5.slave_of = dp6.port
      LEFT JOIN device d1
        ON dp1.ip = d1.ip
      LEFT JOIN device d3
        ON dp5.ip = d3.ip
      LEFT JOIN device d2
        ON dp3.ip = d2.ip
  WHERE dp1.slave_of IS NOT NULL
        AND dp5.ip IS NOT NULL
  ORDER BY d1.dns, dp1.port
ENDSQL
);

__PACKAGE__->add_columns(
  'dns' => {
    data_type => 'text',
  },
  'ip' => {
    data_type => 'inet',
  },
  'port' => {
    data_type => 'text',
  },
  'lag' => {
    data_type => 'text',
  },
  'mid' => {
    data_type => 'text',
  },
  'mid_ip' => {
    data_type => 'inet',
  },
  'mid_port' => {
    data_type => 'text',
  },
  'mid_lag' => {
    data_type => 'text',
  },
  'peer' => {
    data_type => 'text',
  },
  'peer_ip' => {
    data_type => 'inet',
  },
  'peer_port' => {
    data_type => 'text',
  },
  'peer_lag' => {
    data_type => 'text',
  },
);

1;
