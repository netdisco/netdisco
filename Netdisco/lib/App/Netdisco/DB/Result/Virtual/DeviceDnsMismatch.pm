package App::Netdisco::DB::Result::Virtual::DeviceDnsMismatch;

use strict;
use warnings;

use utf8;
use base 'App::Netdisco::DB::Result::Device';

__PACKAGE__->load_components('Helper::Row::SubClass');
__PACKAGE__->subclass;

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table('device_dns_mismatch');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
SELECT *
FROM device
WHERE dns IS NULL
  OR name IS NULL
  OR lower(trim(TRAILING ?
                FROM dns)::text) != lower(trim(TRAILING ?
                                               FROM name)::text)
ENDSQL

1;
