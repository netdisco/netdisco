#line 1
package Module::Install::Share;

use strict;
use Module::Install::Base ();
use File::Find ();
use ExtUtils::Manifest ();

use vars qw{$VERSION @ISA $ISCORE};
BEGIN {
	$VERSION = '1.06';
	@ISA     = 'Module::Install::Base';
	$ISCORE  = 1;
}

sub install_share {
	my $self = shift;
	my $dir  = @_ ? pop   : 'share';
	my $type = @_ ? shift : 'dist';
	unless ( defined $type and $type eq 'module' or $type eq 'dist' ) {
		die "Illegal or invalid share dir type '$type'";
	}
	unless ( defined $dir and -d $dir ) {
    		require Carp;
		Carp::croak("Illegal or missing directory install_share param: '$dir'");
	}

	# Split by type
	my $S = ($^O eq 'MSWin32') ? "\\" : "\/";

	my $root;
	if ( $type eq 'dist' ) {
		die "Too many parameters to install_share" if @_;

		# Set up the install
		$root = "\$(INST_LIB)${S}auto${S}share${S}dist${S}\$(DISTNAME)";
	} else {
		my $module = Module::Install::_CLASS($_[0]);
		unless ( defined $module ) {
			die "Missing or invalid module name '$_[0]'";
		}
		$module =~ s/::/-/g;

		$root = "\$(INST_LIB)${S}auto${S}share${S}module${S}$module";
	}

	my $manifest = -r 'MANIFEST' ? ExtUtils::Manifest::maniread() : undef;
	my $skip_checker = $ExtUtils::Manifest::VERSION >= 1.54
		? ExtUtils::Manifest::maniskip()
		: ExtUtils::Manifest::_maniskip();
	my $postamble = '';
	my $perm_dir = eval($ExtUtils::MakeMaker::VERSION) >= 6.52 ? '$(PERM_DIR)' : 755;
	File::Find::find({
		no_chdir => 1,
		wanted => sub {
			my $path = File::Spec->abs2rel($_, $dir);
			if (-d $_) {
				return if $skip_checker->($File::Find::name);
				$postamble .=<<"END";
\t\$(NOECHO) \$(MKPATH) "$root${S}$path"
\t\$(NOECHO) \$(CHMOD) $perm_dir "$root${S}$path"
END
			}
			else {
				return if ref $manifest
						&& !exists $manifest->{$File::Find::name};
				return if $skip_checker->($File::Find::name);
				$postamble .=<<"END";
\t\$(NOECHO) \$(CP) "$dir${S}$path" "$root${S}$path"
END
			}
		},
	}, $dir);

	# Set up the install
	$self->postamble(<<"END_MAKEFILE");
config ::
$postamble

END_MAKEFILE

	# The above appears to behave incorrectly when used with old versions
	# of ExtUtils::Install (known-bad on RHEL 3, with 5.8.0)
	# So when we need to install a share directory, make sure we add a
	# dependency on a moderately new version of ExtUtils::MakeMaker.
	$self->build_requires( 'ExtUtils::MakeMaker' => '6.11' );

	# 99% of the time we don't want to index a shared dir
	$self->no_index( directory => $dir );
}

1;

__END__

#line 154
