#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catfile catdir updir/;
use FindBin;
use Digest::SHA qw/sha256_hex/;
use JSON::PP ();

# package.json at the repository root is a manifest of the vendored frontend
# libraries under share/public. Its own description says it is not a build step:
# nothing regenerates those files from it, and nothing else checks that what it
# declares is what is shipped.
#
# That gap is not theoretical. Dependabot reads the file as a build input and
# opens pull requests bumping a version line, which changes the declaration and
# not one shipped byte. Merging one leaves the manifest claiming a version the
# repository does not contain, which is worse than declaring nothing, because
# the manifest exists so that a scanner can trust it. A human editing the file
# by hand makes exactly the same mistake, and no bot is needed for it.
#
# So the check is not "are these versions current". It is "does each declared
# version describe the bytes beside it".
#
# Two mechanisms, because the extraction was measured rather than assumed. Most
# of these libraries state their version in the file itself, and reading it back
# ties the declaration to the artifact directly. Four do not, and for those a
# pinned checksum stands in: the table records the version the bytes were taken
# from, and both halves have to agree. A checksum is the stronger assertion
# anyway, since it also catches a vendored file being edited in place, which is
# how share/public/javascripts/d3-3.5.17.min.js came to be byte-identical to
# published d3@3.5.16.

my $root = catdir( $FindBin::Bin, updir() );

my $manifest = do {
    my $path = catfile( $root, 'package.json' );
    open my $fh, '<', $path or die "cannot read $path: $!";
    local $/;
    JSON::PP->new->decode(<$fh>);
};

my $declared = $manifest->{dependencies};

# Each entry names the file that carries the evidence. Where a library ships
# more than one file, this is the one whose version is authoritative; the
# others travel with it in the same re-vendor.
#
# banner: given the declared version, return the pattern that must match the
# file. Built from the declared value on purpose, so that changing package.json
# alone breaks the match.
#
# sha256 + pinned_for: the checksum of the file, and the version it was taken
# from. Re-vendoring changes the bytes; re-declaring changes pinned_for. Either
# on its own is a mismatch.

my @VENDORED = (
    {   package => '@fortawesome/fontawesome-free',
        file    => [qw/css font-awesome.min.css/],
        banner  => sub { qr/Font Awesome Free \Q$_[0]\E\b/ },
    },
    {   package => 'bootstrap',
        file    => [qw/css bootstrap.min.css/],
        banner  => sub { qr/Bootstrap\s+v\Q$_[0]\E\b/ },
    },
    {   # Popper ships no version of its own here. Bootstrap's bundle build
        # inlines it and says so without naming the version, so the bundle's
        # checksum is the only evidence, and re-vendoring Bootstrap is exactly
        # when the inlined Popper changes underneath this line.
        package    => '@popperjs/core',
        file       => [qw/javascripts bootstrap.min.js/],
        sha256     => 'ad1128e83d2d84c09691fafc8fb0842f718361cebb9c608475f732d1d6839d09',
        pinned_for => '2.11.8',
    },
    {   package => 'bootstrap5-toggle',
        file    => [qw/css bootstrap-toggle.min.css/],
        banner  => sub { qr/bootstrap5-toggle v\Q$_[0]\E\b/ },
    },
    {   package => 'datatables.net',
        file    => [qw/javascripts jquery.dataTables.min.js/],
        banner  => sub { qr/DataTables \Q$_[0]\E\b/ },
    },
    {   # The Bootstrap 5 integration layer states which framework it targets
        # and never which version of itself, so there is nothing to read back.
        package    => 'datatables.net-bs5',
        file       => [qw/javascripts dataTables.bootstrap.js/],
        sha256     => '5adfe8c7957aaec56ef0403aa9e1fcdf7165785f092c34bb55c9075ea660ddbc',
        pinned_for => '2.3.8',
    },
    {   # Two reasons rather than one. The banner reads "@version: 3.1" where
        # the manifest declares 3.1.0, so no exact read is possible, and the
        # file is patched locally besides, which a version string cannot show.
        package    => 'daterangepicker',
        file       => [qw/javascripts daterangepicker.js/],
        sha256     => '88e56cd45cad3db88fdc772786d14cce8d0cc1879bc03e4e56be919dfd9ad229',
        pinned_for => '3.1.0',
    },
    {   package => 'jquery',
        file    => [qw/javascripts jquery-latest.min.js/],
        banner  => sub { qr/jQuery v\Q$_[0]\E\b/ },
    },
    {   package => 'jquery-ui',
        file    => [qw/javascripts jquery-ui.min.js/],
        banner  => sub { qr/jQuery UI - v\Q$_[0]\E\b/ },
    },
    {   # The filename says 3.5.17 and the file is 3.5.16. The manifest declares
        # what the bytes say, which is why this reads the internal string and
        # not the name.
        package => 'd3',
        file    => [qw/javascripts d3-3.5.17.min.js/],
        banner  => sub { qr/version:"\Q$_[0]\E"/ },
    },
    {   package => 'moment',
        file    => [qw/javascripts moment.min.js/],
        banner  => sub { qr/version="\Q$_[0]\E"/ },
    },
    {   package => 'jstree',
        file    => [qw/javascripts jstree jstree.min.js/],
        banner  => sub { qr/jsTree - v\Q$_[0]\E\b/ },
    },
    {   package => 'toastr',
        file    => [qw/javascripts toastr.js/],
        banner  => sub { qr/version:\s*'\Q$_[0]\E'/ },
    },
    {   package => 'floatthead',
        file    => [qw/javascripts jquery.floatThead.js/],
        banner  => sub { qr/jQuery\.floatThead \Q$_[0]\E\b/ },
    },
    {   # The bundle carries no usable version of its own: the first x.y.z in it
        # belongs to something else entirely, and a pattern reading that would
        # pass green while describing nothing that is shipped. The drop carries
        # a version-marker.txt written when it was vendored, which is checked
        # below as well, but a file we maintain cannot be the only evidence for
        # a file we did not write.
        package    => 'swagger-ui-dist',
        file       => [qw/swagger-ui swagger-ui-bundle.js/],
        sha256     => '8b188d7d3ee1ce26224908341bb9cdeac67f67f0b68440d2a9ac9e5f73e86d80',
        pinned_for => '5.32.12',
    },
);

sub slurp {
    my $path = shift;
    open my $fh, '<:raw', $path or die "cannot read $path: $!";
    local $/;
    <$fh>;
}

subtest 'vendored_manifest__every_declared_dependency__is_covered_by_this_test' => sub {
    # Without this, adding a library to package.json and no entry here leaves it
    # unchecked while the suite stays green, which is the rot the whole file
    # exists to prevent.
    my %covered = map { $_->{package} => 1 } @VENDORED;

    for my $package ( sort keys %$declared ) {
        ok $covered{$package},
            "$package is covered: add an entry for it to \@VENDORED in "
          . "xt/33-vendored-manifest.t naming the file that carries its version";
    }

    for my $entry (@VENDORED) {
        ok exists $declared->{ $entry->{package} },
            "$entry->{package} is still declared: remove its entry from "
          . "\@VENDORED in xt/33-vendored-manifest.t, or restore it to package.json";
    }
};

for my $entry (@VENDORED) {
    my $package = $entry->{package};
    my $relative = join '/', 'share', 'public', @{ $entry->{file} };
    my $path = catfile( $root, 'share', 'public', @{ $entry->{file} } );

    subtest "vendored_manifest__${package}__ships_the_version_it_declares" => sub {
        my $version = $declared->{$package};

        ok defined $version, "package.json declares a version for $package"
            or return;
        ok -f $path, "$relative is present"
            or return;

        if ( $entry->{banner} ) {
            my $pattern = $entry->{banner}->($version);

            like slurp($path), $pattern,
                "package.json declares $package $version and $relative says so "
              . "too. If they disagree, re-vendor the file or correct the "
              . "manifest, in the same commit.";
        }
        else {
            is $version, $entry->{pinned_for},
                "package.json declares $package $version and this test pins the "
              . "checksum of $relative for $entry->{pinned_for}. Re-vendor the "
              . "file and update the pin here, in the same commit.";

            is sha256_hex( slurp($path) ), $entry->{sha256},
                "$relative is byte-for-byte the $entry->{pinned_for} it is "
              . "pinned as. If the file was re-vendored or edited, update both "
              . "the manifest and the pin in this test, in the same commit.";
        }
    };
}

subtest 'vendored_manifest__swagger_ui_drop__carries_a_marker_matching_the_manifest' => sub {
    # The marker is netdisco's own note of what was vendored, added with the
    # 5.32.12 drop. It is not upstream evidence, so it does not stand in for the
    # checksum above; it is checked so that it cannot quietly go stale and
    # mislead the next person re-vendoring.
    my $path = catfile( $root, 'share', 'public', 'swagger-ui', 'version-marker.txt' );

    ok -f $path, 'share/public/swagger-ui/version-marker.txt is present'
        or return;

    my $marker = slurp($path);
    $marker =~ s/\s+\z//;

    is $marker, $declared->{'swagger-ui-dist'},
        "the marker names the swagger-ui-dist version package.json declares. "
      . "Update share/public/swagger-ui/version-marker.txt when re-vendoring.";
};

done_testing;
