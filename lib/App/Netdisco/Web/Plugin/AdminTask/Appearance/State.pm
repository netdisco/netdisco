package App::Netdisco::Web::Plugin::AdminTask::Appearance::State;
use strict;
use warnings;
use JSON::PP qw(encode_json decode_json);
use File::Basename qw(dirname);
use File::Temp qw(tempfile);
use Fcntl qw(:flock);

sub read_state {
    my ($file) = @_;
    return 0 unless -e $file;
    open my $fh, '<', $file or die "Cannot read appearance settings: $!";
    local $/;
    my $state = decode_json(<$fh>);
    close $fh or die "Cannot close appearance settings: $!";
    die "Invalid appearance settings" unless ref($state) eq 'HASH'
      and defined $state->{classic_colors} and $state->{classic_colors} =~ /\A[01]\z/;
    return 0 + $state->{classic_colors};
}

sub write_state {
    my ($file, $classic) = @_;
    die "Invalid palette" unless defined $classic and $classic =~ /\A[01]\z/;
    open my $lock, '>>', "$file.lock" or die "Cannot lock appearance settings: $!";
    flock($lock, LOCK_EX) or die "Cannot lock appearance settings: $!";
    my ($fh, $tmp) = tempfile('.appearance-XXXXXX', DIR => dirname($file), UNLINK => 1);
    print {$fh} encode_json({classic_colors => 0 + $classic})
      or die "Cannot write appearance settings: $!";
    close $fh or die "Cannot close appearance settings: $!";
    rename $tmp, $file or die "Cannot save appearance settings: $!";
    close $lock;
    return 0 + $classic;
}
1;
