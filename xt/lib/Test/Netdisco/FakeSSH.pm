package Test::Netdisco::FakeSSH;

use strict;
use warnings;

use Carp ();
use Expect ();

=head1 NAME

Test::Netdisco::FakeSSH - scripted Net::OpenSSH stand-in for SSHCollector platforms

=head1 SYNOPSIS

  my $ssh   = Test::Netdisco::FakeSSH->new(fixture => 'xt/data/sshcollector/voss/arp.txt');
  my $guard = $ssh->install_expect;   # collectors call Expect->init($pty)
  my @rows  = $collector->arpnip('label', $ssh, {});
  is_deeply [$ssh->commands], ['terminal more disable', 'show ip arp vrfids 0-512', 'exit'];

  $ssh->timeout_on('show ip arp vrfids 0-512');   # output arrives, prompt never does

=head1 FIXTURE FORMAT

A header line C<#prompt: TEXT> sets the literal prompt (default C<< > >>), then
each C<#--- COMMAND> line starts that command's output, which runs verbatim
to the next C<#---> line. Prompts, blank lines and indentation are kept exactly.
Output is served followed by the prompt; commands are not echoed. A collector that
sends C<exit> needs a C<#--- exit> section. Sending a command with no section dies, listing the known ones. A C<capture> of a command chained with C<' ; '> and having no section of its own is answered by the sections of its parts, joined; a timeout on any part times out the chain. The same table serves
C<capture> (command from the last plain argument, or C<stdin_data>).

=head1 METHODS

C<capture>, C<open2pty>, C<error> mirror Net::OpenSSH. C<open2pty> returns a
pty handle that C<install_expect> makes C<< Expect->init >> accept; the object
it yields supports C<send>, C<expect> (list of C<pos, error, match, before,
after>; on timeout C<pos> is undef and C<error> is C<1:TIMEOUT>, and the partial output stays buffered, as in Expect), C<before>,
C<match>, C<after>, C<raw_pty>, C<log_user>, C<soft_close>, C<hard_close>.
C<commands> lists commands received; C<timeout_on> names one that times out.

=cut

sub new {
    my ($class, %args) = @_;
    my $text = defined $args{text} ? $args{text} : _slurp($args{fixture});
    my $self = bless { prompt => '>', table => {}, commands => [],
                       timeouts => {}, error => '' }, $class;
    $self->_parse($text);
    return $self;
}

sub _slurp {
    my ($path) = @_;
    Carp::croak('Test::Netdisco::FakeSSH->new needs fixture => $path or text => $string')
        unless defined $path;
    open my $fh, '<', $path or Carp::croak("cannot read fixture $path: $!");
    local $/;
    return scalar <$fh>;
}

sub _parse {
    my ($self, $text) = @_;
    my $command;
    for my $line (split /(?<=\n)/, $text) {
        if ($line =~ /\A#prompt: ?(.*?)\r?\n?\z/ and !defined $command) {
            $self->{prompt} = $1;
        }
        elsif ($line =~ /\A#--- (.*?)\r?\n?\z/) {
            $command = $1;
            $self->{table}{$command} = '';
        }
        elsif (defined $command) {
            $self->{table}{$command} .= $line;
        }
    }
}

sub commands   { return @{ $_[0]{commands} } }
sub error      { return $_[0]{error} }
sub timeout_on { $_[0]{timeouts}{$_[1]} = 1; return $_[0] }

sub _output_for {
    my ($self, $command) = @_;
    return $self->{table}{$command} if exists $self->{table}{$command};
    Carp::croak(sprintf "FakeSSH has no fixture section for command '%s'; known: %s",
        $command, join ', ', map { "'$_'" } sort keys %{ $self->{table} });
}

sub capture {
    my $self = shift;
    my $opts = (ref $_[0] eq 'HASH') ? shift : {};
    my $command = defined $opts->{stdin_data} ? $opts->{stdin_data} : $_[-1];
    Carp::croak('FakeSSH->capture needs a command argument or stdin_data') unless defined $command;
    $command =~ s/\r?\n\z//;

    push @{ $self->{commands} }, $command;
    $self->{error} = '';
    # a chain "a ; b" with no section of its own answers each part in turn,
    # one document per line as NX-OS prints them
    my @parts = (exists $self->{table}{$command} ? ($command) : split / ; /, $command);
    my $output = join '', map {
        my $part = $self->_output_for($_);
        (length $part and $part !~ /\n\z/) ? "$part\n" : $part;
    } @parts;
    if (grep { $self->{timeouts}{$_} } $command, @parts) {
        $self->{error} = "command '$command' timed out";
        return wantarray ? () : '';
    }
    return wantarray ? (split /(?<=\n)/, $output) : $output;
}

sub open2pty {
    my ($self) = @_;
    $self->{error} = '';
    return (Test::Netdisco::FakeSSH::Pty->new($self), 4242);
}

# Expect->init is a plain class method on a real filehandle; swap it for the
# life of the returned guard so collectors run unmodified.
sub install_expect {
    my ($self) = @_;
    my $original = \&Expect::init;
    no warnings 'redefine';
    *Expect::init = sub {
        my ($class, $pty) = @_;
        return $original->(@_) unless ref $pty eq 'Test::Netdisco::FakeSSH::Pty';
        return Test::Netdisco::FakeSSH::Expect->new($pty->{ssh});
    };
    return bless { original => $original }, 'Test::Netdisco::FakeSSH::Guard';
}

package Test::Netdisco::FakeSSH::Guard;

sub DESTROY {
    no warnings 'redefine';
    *Expect::init = $_[0]{original};
}

package Test::Netdisco::FakeSSH::Pty;

sub new { return bless { ssh => $_[1] }, $_[0] }

package Test::Netdisco::FakeSSH::Expect;

sub new {
    my ($class, $ssh) = @_;
    return bless { ssh => $ssh, buffer => $ssh->{prompt}, before => '',
                   match => undef, after => '' }, $class;
}

sub send {
    my ($self, $text) = @_;
    my $ssh = $self->{ssh};
    for my $command (split /\r?\n/, $text) {
        push @{ $ssh->{commands} }, $command;
        my $output = $ssh->_output_for($command);
        $self->{buffer} .= $output;
        $self->{buffer} .= $ssh->{prompt} unless $ssh->{timeouts}{$command};
    }
    return 1;
}

sub expect {
    my ($self, $timeout, @patterns) = @_;
    my @regexes = grep { ref $_ eq 'Regexp' } @patterns;
    my $buffer  = $self->{buffer};

    for my $index (0 .. $#regexes) {
        next unless $buffer =~ $regexes[$index];
        @{$self}{qw(before match after)} = ($`, $&, $');
        $self->{buffer} = $';
        return ($index + 1, undef, $&, $`, $');
    }

    @{$self}{qw(before match after)} = ($buffer, undef, '');
    return (undef, '1:TIMEOUT', undef, $buffer, '');
}

sub before     { return $_[0]{before} }
sub match      { return $_[0]{match} }
sub after      { return $_[0]{after} }
sub raw_pty    { return 1 }
sub log_user   { return 0 }
sub soft_close { return 1 }
sub hard_close { return 1 }

1;
