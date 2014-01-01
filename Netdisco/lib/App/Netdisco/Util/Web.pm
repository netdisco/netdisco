package App::Netdisco::Util::Web;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  sort_port
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Web

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 sort_port( $a, $b )

Sort port names of various types used by device vendors. Interface is as
Perl's own C<sort> - two input args and an integer return value.

=cut

sub sort_port {
    my ($aval, $bval) = @_;

    # hack for foundry "10GigabitEthernet" -> cisco-like "TenGigabitEthernet"
    $aval = $1 if $aval =~ qr/^10(GigabitEthernet.+)$/;
    $bval = $1 if $bval =~ qr/^10(GigabitEthernet.+)$/;

    my $numbers        = qr{^(\d+)$};
    my $numeric        = qr{^([\d\.]+)$};
    my $dotted_numeric = qr{^(\d+)[:.](\d+)$};
    my $letter_number  = qr{^([a-zA-Z]+)(\d+)$};
    my $wordcharword   = qr{^([^:\/.]+)[-\ :\/\.]+([^:\/.0-9]+)(\d+)?$}; #port-channel45
    my $netgear        = qr{^Slot: (\d+) Port: (\d+) }; # "Slot: 0 Port: 15 Gigabit - Level"
    my $ciscofast      = qr{^
                            # Word Number slash (Gigabit0/)
                            (\D+)(\d+)[\/:]
                            # Groups of symbol float (/5.5/5.5/5.5), separated by slash or colon
                            ([\/:\.\d]+)
                            # Optional dash (-Bearer Channel)
                            (-.*)?
                            $}x;

    my @a = (); my @b = ();

    if ($aval =~ $dotted_numeric) {
        @a = ($1,$2);
    } elsif ($aval =~ $letter_number) {
        @a = ($1,$2);
    } elsif ($aval =~ $netgear) {
        @a = ($1,$2);
    } elsif ($aval =~ $numbers) {
        @a = ($1);
    } elsif ($aval =~ $ciscofast) {
        @a = ($1,$2);
        push @a, split(/[:\/]/,$3), $4;
    } elsif ($aval =~ $wordcharword) {
        @a = ($1,$2,$3);
    } else {
        @a = ($aval);
    }

    if ($bval =~ $dotted_numeric) {
        @b = ($1,$2);
    } elsif ($bval =~ $letter_number) {
        @b = ($1,$2);
    } elsif ($bval =~ $netgear) {
        @b = ($1,$2);
    } elsif ($bval =~ $numbers) {
        @b = ($1);
    } elsif ($bval =~ $ciscofast) {
        @b = ($1,$2);
        push @b, split(/[:\/]/,$3),$4;
    } elsif ($bval =~ $wordcharword) {
        @b = ($1,$2,$3);
    } else {
        @b = ($bval);
    }

    # Equal until proven otherwise
    my $val = 0;
    while (scalar(@a) or scalar(@b)){
        # carried around from the last find.
        last if $val != 0;

        my $a1 = shift @a;
        my $b1 = shift @b;

        # A has more components - loses
        unless (defined $b1){
            $val = 1;
            last;
        }

        # A has less components - wins
        unless (defined $a1) {
            $val = -1;
            last;
        }

        if ($a1 =~ $numeric and $b1 =~ $numeric){
            $val = $a1 <=> $b1;
        } elsif ($a1 ne $b1) {
            $val = $a1 cmp $b1;
        }
    }

    return $val;
}

=head2 sort_modules( $modules )

Sort devices modules into tree hierarchy based upon position and parent -
input arg is module list.

=cut

sub sort_modules {
    my $input = shift;
    my %modules;

    foreach my $module (@$input) {
        $modules{$module->index}{module} = $module;
        if ($module->parent) {
            # Example
            # index |              description               |        type         | parent |  class  | pos 
            #-------+----------------------------------------+---------------------+--------+---------+-----
            #     1 | Cisco Aironet 1200 Series Access Point | cevChassisAIRAP1210 |      0 | chassis |  -1
            #     3 | PowerPC405GP Ethernet                  | cevPortFEIP         |      1 | port    |  -1
            #     2 | 802.11G Radio                          | cevPortUnknown      |      1 | port    |   0

            # Some devices do not implement correctly, so given parent
            # can have multiple items within the same class at a single pos
            # value.  However, the database results are sorted by 1) parent
            # 2) class 3) pos 4) index so we should just be able to push onto
            # the array and ordering be preserved.
            push(@{$modules{$module->parent}{children}{$module->class}}, $module->index);
        } else {
            push(@{$modules{root}}, $module->index);
        }
    }
    return \%modules;
}

1;
