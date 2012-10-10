#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Dancer ':script';
use Dancer::Plugin::DBIC 'schema';

use Netdisco::DB;
use Try::Tiny;
use feature 'say';

try {
  my $count = schema->resultset('Device')->count();
}
catch {
  # fresh install? deploy the Netdisco::DB schema
  say 'Deploying Netdisco::DB schema...';
  schema->txn_do(sub { schema->deploy() });
  exec $0;
};

if (not schema->get_db_version()) {
  # installs the dbix_class_schema_versions table with version "0"
  say 'Installing DBIx::Class versioning to Netdisco::DB schema...';
  schema->txn_do(sub { schema->install("1") });
  exec $0;
}

# upgrades from whatever dbix_class_schema_versions says, to $VERSION
say 'Upgrading Netdisco::DB schema...';
schema->txn_do(sub { schema->upgrade() });
