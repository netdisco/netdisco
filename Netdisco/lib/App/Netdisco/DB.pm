use utf8;
package App::Netdisco::DB;

use strict;
use warnings;

use base 'DBIx::Class::Schema';

__PACKAGE__->load_namespaces;

our $VERSION = 24; # schema version used for upgrades, keep as integer

use Path::Class;
use File::Basename;

my (undef, $libpath, undef) = fileparse( $INC{ 'App/Netdisco/DB.pm' } );
our $schema_versions_dir = Path::Class::Dir->new($libpath)
  ->subdir("DB", "schema_versions")->stringify;

__PACKAGE__->load_components(qw/
  Schema::Versioned
  +App::Netdisco::DB::ExplicitLocking
/);

__PACKAGE__->upgrade_directory($schema_versions_dir);

1;
