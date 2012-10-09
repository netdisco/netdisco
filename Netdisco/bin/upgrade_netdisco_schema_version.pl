#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Dancer ':script';
use Dancer::Plugin::DBIC 'schema';

use Netdisco::DB;
use Try::Tiny;

if (not schema->get_db_version()) {
  # installs the dbix_class_schema_versions table with version "0"
  schema->install("0");
}

# upgrades from whatever dbix_class_schema_versions says, to $VERSION
schema->upgrade();
