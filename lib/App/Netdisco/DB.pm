use utf8;
package App::Netdisco::DB;

use strict;
use warnings;

use base 'DBIx::Class::Schema';

__PACKAGE__->load_namespaces(
    default_resultset_class => 'ResultSet',
);

our # try to hide from kwalitee
  $VERSION = 95; # schema version used for upgrades, keep as integer

use Path::Class;
use File::ShareDir 'dist_dir';

our $schema_versions_dir = Path::Class::Dir->new( dist_dir('App-Netdisco') )
  ->subdir('schema_versions')->stringify;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::SchemaVersioned
  +App::Netdisco::DB::ExplicitLocking
/);

__PACKAGE__->upgrade_directory($schema_versions_dir);

1;
