package SQL::Translator::Netdisco::Utils;

use strict;
use warnings;

our @EXPORT;
BEGIN {
    use base 'Exporter';
    @EXPORT = qw/ make_path make_label /;
}

sub make_path {
    my $rs = shift;

    my $from = ref $rs->from ? ${$rs->from} : $rs->from;
    return lc $from if $from =~ m/^\w+$/;

    my $name = $rs->source_name;
    $name =~ s/([a-z])([A-Z])/$1_$2/g;
    $name =~ s/([a-zA-Z])([0-9])/$1_$2/g;
    $name =~ s/([0-9])([A-Za-z])/$1_$2/g;
    return lc $name;
}

my @acronyms = qw(
  FRU
  IP
  FW
  SW
  HW
  VLAN
  MAC
  OUI
  LDAP
  DNS
  OS
  PS
);

sub make_label {
    my $text = shift;
    $text =~ s/^.+:://;
    $text =~ s/([a-z])([A-Z])/$1_$2/g;
    $text =~ s/([a-zA-Z])([0-9])/$1_$2/g;
    $text =~ s/([0-9])([A-Za-z])/$1_$2/g;

    my $label = join ' ', map ucfirst, split /[\W_]+/, lc $text;
    $label =~ s/\b$_\b/$_/ig for @acronyms;
    return $label;
}

1;
