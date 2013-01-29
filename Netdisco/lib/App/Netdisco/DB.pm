use utf8;
package App::Netdisco::DB;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Schema';

__PACKAGE__->load_namespaces;


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:tQTf/oInVydRDsuIFLSU4A

our $VERSION = 4; # schema version used for upgrades, keep as integer

use Path::Class;
use File::Basename;

my (undef, $libpath, undef) = fileparse( $INC{ 'App/Netdisco/DB.pm' } );
our $schema_versions_dir = Path::Class::Dir->new($libpath)
  ->subdir("DB", "schema_versions")->stringify;

__PACKAGE__->load_components(qw/Schema::Versioned/);
__PACKAGE__->upgrade_directory($schema_versions_dir);

# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
