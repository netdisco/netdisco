#!/usr/bin/env perl

# The Device Search "fields" parameter names the SELECT list, so
# _requested_fields() resolves it against the Device result source's own
# columns, minus the stored community, plus the one supported join alias. A
# name it does not know means the request is refused rather than repaired,
# and nothing from the request is echoed back.
#
# Everything else about the parameter has to keep working exactly as it did,
# which is what most of this file is for.
#
# A name is matched the way Postgres would read it: an unquoted identifier
# folds to lower case over ASCII alone, and only ASCII whitespace is stripped
# around one. Matching more widely than that, with Perl's lc and \s, would
# accept names the database always rejected, U+212A KELVIN SIGN and U+00A0
# NO-BREAK SPACE among them.
#
# The name that matched is what the database is asked for, but the key the
# caller reads back is the name they sent, held on the perl side by DBIC's
# label form. That is load bearing: "IP,DNS" fails the collapse because the
# collapse needs the primary key labelled exactly "ip". Selecting "me.ip"
# under the key "ip" instead would quietly make an input work that never
# worked.
#
# The cases for a "fields" that is given but names no usable column, and for
# one asking only for the auth tag, assert the whole selectable list rather
# than the defaults. That is deliberate: both of those select every column,
# so answering them with the defaults would quietly hand a documented input a
# different set of ordinary columns. Only the credential goes.
#
# The allow-list is read from the shipped Device result source rather than
# from a copy kept here, so adding a column to the table does not need this
# file edited, and a column added to %SECRET_FIELDS is seen at once.
#
# THIS IS A HELPER-LEVEL TEST. The route is require_login and the auth
# provider is DBIC, which no config setting bypasses, so as in
# xt/36-ajax-content-response.t the response itself cannot be driven from
# here. The result source needs no database to answer ->columns. Where a
# case below says a query dies in the database, that was measured against a
# real one; what is asserted here is the SELECT list which produces it.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use FindBin;
use File::Spec::Functions qw/catfile updir/;

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Web::Plugin::Search::Device;

my $SECRET_COLUMN = 'snmp_comm';
my $AUTH_TAG      = 'device_auth_tag';

# the default set the API documents, which an absent "fields" must still give
my @DOCUMENTED_DEFAULTS =
  qw/ip dns name location model os_ver serial chassis_id/;

my $device_source = App::Netdisco::DB->source('Device');
my @all_columns   = $device_source->columns;
my @selectable    = grep { $_ ne $SECRET_COLUMN } @all_columns;

sub resolve {
    return App::Netdisco::Web::Plugin::Search::Device::_requested_fields(
      $device_source, shift );
}

# the selected columns, or nothing at all if the request was refused, so that
# a refusal reads as a failed comparison rather than dying on undef
sub cols {
    my $select = resolve(shift);
    return $select ? $select->{columns} : undef;
}

# the key the caller reads each field back under
sub labels {
    my $cols = cols(shift) or return undef;
    return [ map { ref $_ ? (keys %$_)[0] : $_ } @$cols ];
}

# what the database is actually asked for
sub sources {
    my $cols = cols(shift) or return undef;
    return [ map { ref $_ ? (values %$_)[0] : $_ } @$cols ];
}

subtest 'deviceTable__the_column_this_guard_protects__is_still_in_the_schema' => sub {
    ok( scalar( grep { $_ eq $SECRET_COLUMN } @all_columns ),
      "Device still has a $SECRET_COLUMN column" );
    cmp_ok( scalar @selectable, '>', scalar @DOCUMENTED_DEFAULTS,
      'there are more selectable columns than the documented defaults' );
    is_deeply( [ grep { my $c = $_; ! grep { $_ eq $c } @all_columns }
                 @DOCUMENTED_DEFAULTS ], [],
      'every documented default is a real Device column' );
};

subtest 'requestedFields__no_fields_parameter__returns_the_documented_defaults' => sub {
    my $select = resolve('');
    ok( $select, 'an absent "fields" is accepted' );
    is_deeply( $select->{columns}, [@DOCUMENTED_DEFAULTS],
      'the defaults are selected, unchanged' );
    ok( ! $select->{want_tag}, 'the community table is not joined' );
};

subtest 'requestedFields__fields_all__returns_every_column_but_the_community' => sub {
    my $select = resolve('all');
    ok( $select, '"all" is accepted' );
    is_deeply( [ sort @{ $select->{columns} } ], [ sort @selectable ],
      'every selectable column is selected' );
    ok( ! scalar( grep { $_ eq $SECRET_COLUMN } @{ $select->{columns} } ),
      "$SECRET_COLUMN is not among them" );
    cmp_ok( scalar @{ $select->{columns} }, '>', scalar @DOCUMENTED_DEFAULTS,
      'more than the defaults are selected' );

    # "ALL" reached the database as me.ALL, which is no column in any case
    ok( ! resolve('ALL'), 'the keyword is matched exactly, as it always was' );
};

subtest 'requestedFields__a_field_list_naming_nothing__returns_every_selectable_column' => sub {
    my $select = resolve(',');
    ok( $select, 'a "fields" of punctuation alone is accepted' );
    is_deeply( [ sort @{ $select->{columns} } ], [ sort @selectable ],
      'every selectable column is selected, as before this list existed' );
    ok( ! scalar( grep { $_ eq $SECRET_COLUMN } @{ $select->{columns} } ),
      "$SECRET_COLUMN is not among them" );
    cmp_ok( scalar @{ $select->{columns} }, '>', scalar @DOCUMENTED_DEFAULTS,
      'more than the defaults are selected' );
};

subtest 'requestedFields__the_auth_tag_alone__returns_every_selectable_column' => sub {
    my $select = resolve($AUTH_TAG);
    ok( $select, 'the join alias on its own is accepted' );
    is_deeply( [ sort @{ $select->{columns} } ], [ sort @selectable ],
      'every selectable column is selected, as before this list existed' );
    ok( ! scalar( grep { $_ eq $SECRET_COLUMN } @{ $select->{columns} } ),
      "$SECRET_COLUMN is not among them" );
    cmp_ok( scalar @{ $select->{columns} }, '>', scalar @DOCUMENTED_DEFAULTS,
      'more than the defaults are selected' );
    ok( $select->{want_tag}, 'the community table is joined for the tag' );
    ok( ! scalar( grep { $_ eq $AUTH_TAG } @{ $select->{columns} } ),
      'the alias itself is not asked of the device table' );
};

subtest 'requestedFields__an_explicit_column_list__returns_only_those_columns' => sub {
    my $select = resolve('ip,dns');
    is_deeply( $select->{columns}, [qw/ip dns/], 'just what was asked for' );
    ok( ! $select->{want_tag}, 'the community table is not joined' );

    is_deeply( cols('ip, dns'), [qw/ip dns/],
      'a space after the comma is still just what was asked for' );
};

subtest 'requestedFields__a_name_in_capitals__is_read_back_under_the_capitals' => sub {
    is_deeply( labels('ip,DNS'), [qw/ip DNS/],
      'the caller reads the field back under the name they sent' );
    is_deeply( sources('ip,DNS'), [qw/ip me.dns/],
      'the database is asked for the column the name matched' );

    is_deeply( labels('IP,DNS'), [qw/IP DNS/],
      'a capitalized primary key is still labelled as the caller sent it' );
    ok( ! scalar( grep { $_ eq 'ip' } @{ labels('IP,DNS') } ),
      'so the collapse still has no column labelled ip, and still fails' );

    my $shouted_tag = resolve(uc $AUTH_TAG);
    ok( ( $shouted_tag && ! $shouted_tag->{want_tag} ),
      'a capitalized join alias is not the join alias, as it never was' );
    is_deeply( sources(uc $AUTH_TAG), ["me.$AUTH_TAG"],
      'it is a device column the database does not have, exactly as before' );
};

subtest 'requestedFields__a_name_with_space_around_it__keeps_the_space_in_its_key' => sub {
    is_deeply( labels('ip,dns '), ['ip', 'dns '],
      'a trailing space is part of the key, as it always was' );
    is_deeply( sources('ip,dns '), [qw/ip me.dns/],
      'the database is asked for the column without it' );

    is_deeply( labels("ip,dns\t"), ['ip', "dns\t"],
      'a trailing tab is part of the key too' );

    is_deeply( labels(' ip , dns '), [' ip', 'dns '],
      'space the comma split did not eat stays in the key' );
    ok( ! scalar( grep { $_ eq 'ip' } @{ labels(' ip , dns ') } ),
      'so the collapse still has no column labelled ip, and still fails' );
};

subtest 'requestedFields__a_name_outside_ascii__is_refused' => sub {
    ok( ! resolve("last_macsuc\x{212A}"),
      'a KELVIN SIGN is not a K to Postgres, and is not folded into one here' );
    ok( ! resolve("ip,\x{A0}dns"),
      'a NO-BREAK SPACE is not whitespace to Postgres, and is not trimmed here' );
    ok( ! resolve("\x{A0}ip,dns"),
      'the same in front of the primary key' );
    ok( ! resolve("ip,dns\x{2003}"),
      'an EM SPACE is not trimmed here either' );
};

subtest 'requestedFields__whatever_the_caller_sends__the_database_sees_only_a_column' => sub {
    my %is_column = map {$_ => 1} @all_columns, $AUTH_TAG;

    foreach my $fields ('', 'all', ',', $AUTH_TAG, 'ip,dns', 'ip,DNS', 'ip,dns ',
                        "ip,dns\t", 'IP,DNS', ' ip , dns ', uc $AUTH_TAG) {
        my $sources = sources($fields) or next;
        my @outside = grep { my $c = $_; $c =~ s/\Ame\.//; ! $is_column{$c} }
                      @$sources;
        is_deeply( \@outside, [],
          "nothing but a column name is asked of the database for <$fields>" );
    }
};

subtest 'requestedFields__the_stored_community__is_refused' => sub {
    ok( ! resolve($SECRET_COLUMN), "$SECRET_COLUMN on its own is refused" );
    ok( ! resolve("ip,$SECRET_COLUMN"), "$SECRET_COLUMN alongside a column is refused" );
    ok( ! resolve("$SECRET_COLUMN,$AUTH_TAG"),
      "$SECRET_COLUMN alongside the join alias is refused" );
    ok( ! resolve(uc $SECRET_COLUMN),
      "$SECRET_COLUMN in capitals is refused" );
    ok( ! resolve(" $SECRET_COLUMN "),
      "$SECRET_COLUMN padded with space is refused" );
};

subtest 'requestedFields__a_name_that_is_not_a_column__is_refused' => sub {
    ok( ! resolve('bogus'), 'an unknown name is refused' );
    ok( ! resolve('ip,bogus'), 'an unknown name alongside a column is refused' );
    ok( ! resolve('device_port.name'),
      'a column of another table is refused' );
    ok( ! resolve('*'), 'a wildcard is refused' );
    ok( ! resolve(' '), 'a name which is nothing but space is refused' );
};

subtest 'requestedFields__a_sql_expression__is_refused' => sub {
    ok( ! resolve('ip,(select 1)'), 'a parenthesized expression is refused' );
    ok( ! resolve('ip,ip||dns'),
      'an operator joining two real columns is refused' );
    ok( ! resolve('ip,ip --'), 'a name carrying a comment marker is refused' );
    ok( ! resolve('ip;select 1'), 'a statement terminator is refused' );
    ok( ! resolve('me.ip'), 'a qualified column name is refused' );
    ok( ! resolve('ME.IP'), 'a qualified column name in capitals is refused' );
    ok( ! resolve('ip ; select 1'),
      'space inside a name is not trimmed away into a column name' );
};

subtest 'deviceSearchHandler__the_select_list__comes_from_the_resolver' => sub {
    my $module = catfile( $FindBin::RealBin, updir(), 'lib', 'App',
      'Netdisco', 'Web', 'Plugin', 'Search', 'Device.pm' );

    my $source = do {
        open my $fh, '<', $module or die "cannot read $module: $!";
        local $/;
        <$fh>;
    };

    like( $source, qr/->columns\(\s*\$\w+->\{columns\}\s*\)/,
      'the handler selects the columns the resolver returned' );
};

done_testing;
