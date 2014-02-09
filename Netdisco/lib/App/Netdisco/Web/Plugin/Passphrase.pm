package App::Netdisco::Web::Plugin::Passphrase;

# ABSTRACT: Passphrases and Passwords as objects for Dancer

=head1 NAME

Dancer::Plugin::Passphrase - Passphrases and Passwords as objects for Dancer

=head1 SYNOPSIS

This plugin manages the hashing of passwords for Dancer apps, allowing 
developers to follow cryptography best practices without having to 
become a cryptography expert.

It uses the bcrypt algorithm as the default, while also supporting any
hashing function provided by L<Digest> 

=head1 USAGE

    package MyWebService;
    use Dancer ':syntax';
    use Dancer::Plugin::Passphrase;

    post '/login' => sub {
        my $phrase = passphrase( param('my password') )->generate;

        # $phrase is now an object that contains RFC 2307 representation
        # of the hashed passphrase, along with the salt, and other metadata
        
        # You should store $phrase->rfc2307() for use later
    };

    get '/protected' => sub {
        # Retrieve $stored_rfc_2307_string, like we created above.
        # IT MUST be a valid RFC 2307 string

        if ( passphrase( param('my password') )->matches( $stored_rfc_2307 ) ) {
            # Passphrase matches!
        }
    };

    get '/generate_new_password' => sub {
        return passphrase->generate_random;
    };

=cut

use strict;
use feature 'switch';

use Dancer::Plugin;

use Carp qw(carp croak);
use Data::Entropy::Algorithms qw(rand_bits rand_int);
use Digest;
use MIME::Base64 qw(decode_base64 encode_base64);
use Scalar::Util qw(blessed);

our $VERSION = '2.0.0';

# Auto stringifies and returns the RFC 2307 representation
# of the object unless we are calling a method on it
use overload (
    '""' => sub {
        if (blessed($_[0]) && $_[0]->isa('App::Netdisco::Web::Plugin::Passphrase')) {
            $_[0]->rfc2307();
        }
    },
    fallback => 1,
);

register passphrase => \&passphrase;


=head1 KEYWORDS

=head2 passphrase

Given a plaintext password, it returns a Dancer::Plugin::Passphrase 
object that you can generate a new hash from, or match against a stored hash.

=cut

sub passphrase {
    # Dancer 2 keywords receive a reference to the DSL object as a first param.
    # We don't need it, so get rid of it, and just get the plaintext
    shift if blessed($_[0]) && $_[0]->isa('Dancer::Core::DSL');

    my $plaintext = $_[0];

    return bless {
        plaintext => $plaintext
    }, 'App::Netdisco::Web::Plugin::Passphrase';
}



=head1 MAIN METHODS

=head2 generate

Generates an RFC 2307 representation of the hashed passphrase
that is suitable for storage in a database.

    my $pass = passphrase('my passphrase')->generate;

You should store C<$phrase->rfc_2307()> in your database. For convenience
the object will automagically return the RFC 2307 representation when no
method is called on it.

Accepts a hashref of options to specify what kind of hash should be 
generated. All options settable in the config file are valid.

If you specify only the algorithm, the default settings for that algorithm will be used.

A cryptographically random salt is used if salt is not defined.
Only if you specify the empty string will an empty salt be used
This is not recommended, and should only be used to upgrade old insecure hashes

    my $phrase = passphrase('my password')->generate({
        algorithm  => '',   # What algorithm is used to generate the hash
        cost       => '',   # Cost / Work Factor if using bcrypt
        salt       => '',   # Manually specify salt if using a salted digest
    });

=cut

sub generate {
    my ($self, $options) = @_;

    $self->_get_settings($options);
    $self->_calculate_hash;

    return $self;
}

sub generate_hash {
    carp "generate_hash method is deprecated";
    return shift->generate();
}


=head2 matches

Matches a plaintext password against a stored hash.
Returns 1 if the hash of the password matches the stored hash.
Returns undef if they don't match or if there was an error
Fail-Secure, rather than Fail-Safe.

    passphrase('my password')->matches($stored_rfc_2307_string);

$stored_rfc_2307_string B<MUST> be a valid RFC 2307 string,
as created by L<generate()|/"passphrase__generate">

An RFC 2307 string is made up of a scheme identifier, followed by a
base64 encoded string. The base64 encoded string should contain
the password hash and the salt concatenated together - in that order.

    '{'.$scheme.'}'.encode_base64($hash . $salt, '');

Where C<$scheme> can be any of the following and their unsalted variants,
which have the leading S removed. CRYPT will be Bcrypt.

    SMD5 SSHA SSHA224 SSHA256 SSHA384 SSHA512 CRYPT

A complete RFC2307 string looks like this:

    {SSHA}K3LAbIjRL5CpLzOlm3/HzS3qt/hUaGVTYWx0

This is the format created by L<generate()|/"passphrase__generate">

=cut

sub matches {
    my ($self, $stored_hash) = @_;

    # Force auto stringification in case we were passed an object.
    ($stored_hash) = ($stored_hash =~ m/(.*)/s);

    my $new_hash = $self->_extract_settings($stored_hash)->_calculate_hash->rfc2307;

    return ($new_hash eq $stored_hash) ? 1 : undef;
}



=head2 generate_random

Generates and returns any number of cryptographically random
characters from the url-safe base64 charater set.

    my $rand_pass = passphrase->generate_random;

The passwords generated are suitable for use as
temporary passwords or one-time authentication tokens.

You can configure the length and the character set
used by passing a hashref of options.

    my $rand_pass = passphrase->generate_random({
        length  => 32,
        charset => ['a'..'z', 'A'..'Z'],
    });

=cut

sub generate_random {
    my ($self, $options) = @_;

    # Default is 16 URL-safe base64 chars. Supported everywhere and a reasonable length
    my $length  = $options->{length}  || 16;
    my $charset = $options->{charset} || ['a'..'z', 'A'..'Z', '0'..'9', '-', '_'];

    return join '', map { @$charset[rand_int scalar @$charset] } 1..$length;
}



=head1 ADDITIONAL METHODS

The methods are only applicable once you have called C<generate>

    passphrase( 'my password' )->generate->rfc2307; # CORRECT

    passphrase( 'my password' )->rfc2307;           # INCORRECT, Returns undef


=head2 rfc2307

Returns the rfc2307 representation from a C<Dancer::Plugin::Passphrase> object.

    passphrase('my password')->generate->rfc2307;

=cut

sub rfc2307 {
    return shift->{rfc2307} || undef;
}

sub as_rfc2307 {
    carp "as_rfc2307 method is deprecated";
    return shift->rfc2307();
}



=head2 scheme

Returns the scheme name from a C<Dancer::Plugin::Passphrase> object.

This is the scheme name as used in the RFC 2307 representation

    passphrase('my password')->generate->scheme;

The scheme name can be any of the following, and will always be capitalized

    SMD5  SSHA  SSHA224  SSHA256  SSHA384  SSHA512  CRYPT
    MD5   SHA   SHA224   SHA256   SHA384   SHA512

=cut

sub scheme {
    return shift->{scheme} || undef;
}


=head2 algorithm

Returns the algorithm name from a C<Dancer::Plugin::Passphrase> object.

The algorithm name can be anything that is accepted by C<Digest->new($alg)>
This includes any modules in the C<Digest::> Namespace

    passphrase('my password')->generate->algorithm;

=cut

sub algorithm {
    return shift->{algorithm} || undef;
}


=head2 cost

Returns the bcrypt cost from a C<Dancer::Plugin::Passphrase> object.
Only works when using the bcrypt algorithm, returns undef for other algorithms

    passphrase('my password')->generate->cost;

=cut

sub cost {
    return shift->{cost} || undef;
}


=head2 salt_raw

Returns the raw salt from a C<Dancer::Plugin::Passphrase> object.

    passphrase('my password')->generate->salt_raw;

Can be defined, but false - The empty string is technically a valid salt.

Returns C<undef> if there is no salt.

=cut

sub salt_raw {
    return shift->{salt} // undef;
}

sub raw_salt {
    carp "raw_salt method is deprecated";
    return shift->salt_raw();
}

=head2 hash_raw

Returns the raw hash from a C<Dancer::Plugin::Passphrase> object.

    passphrase('my password')->generate->hash_raw;

=cut

sub hash_raw {
    return shift->{hash} || undef;
}

sub raw_hash {
    carp "raw_hash method is deprecated";
    return shift->hash_raw();
}


=head2 salt_hex

Returns the hex-encoded salt from a C<Dancer::Plugin::Passphrase> object.

Can be defined, but false - The empty string is technically a valid salt.
Returns C<undef> if there is no salt.

    passphrase('my password')->generate->salt_hex;

=cut

sub salt_hex {
    return unpack("H*", shift->{salt}) // undef;
}


=head2 hash_hex

Returns the hex-encoded hash from a C<Dancer::Plugin::Passphrase> object.

    passphrase('my password')->generate->hash_hex;

=cut

sub hash_hex {
    return unpack("H*", shift->{hash}) || undef;
}


=head2 salt_base64

Returns the base64 encoded salt from a C<Dancer::Plugin::Passphrase> object.

Can be defined, but false - The empty string is technically a valid salt.
Returns C<undef> if there is no salt.

    passphrase('my password')->generate->salt_base64;

=cut

sub salt_base64 {
    return encode_base64(shift->{salt}, '') // undef;
}


=head2 hash_base64

Returns the base64 encoded hash from a C<Dancer::Plugin::Passphrase> object.

    passphrase('my password')->generate->hash_base64;

=cut

sub hash_base64 {
    return encode_base64(shift->{hash}, '') || undef;
}

=head2 plaintext

Returns the plaintext password as originally supplied to the L<passphrase> keyword.

    passphrase('my password')->generate->plaintext;

=cut

sub plaintext {
    return shift->{plaintext} || undef;
}



# Actual generation of the hash, using the provided settings
sub _calculate_hash {
    my $self = shift;

    my $hasher = Digest->new( $self->algorithm );

    given ($self->algorithm) {
        when ('Bcrypt') {
            $hasher->add($self->{plaintext});
            $hasher->salt($self->salt_raw);
            $hasher->cost($self->cost);

            $self->{hash} = $hasher->digest;
            $self->{rfc2307}
                = '{CRYPT}$'
                . $self->{type} . '$'
                . $self->cost . '$'
                . _en_bcrypt_base64($self->salt_raw)
                . _en_bcrypt_base64($self->hash_raw);
        }
        default {
            $hasher->add($self->{plaintext});
            $hasher->add($self->{salt});

            $self->{hash} = $hasher->digest;
            $self->{rfc2307}
                = '{' . $self->{scheme} . '}'
                . encode_base64($self->hash_raw . $self->salt_raw, '');
        }
    }

    return $self;
}


# Extracts the settings from an RFC 2307 string
sub _extract_settings {
    my ($self, $rfc2307_string) = @_;

    my ($scheme, $settings) = ($rfc2307_string =~ m/^{(\w+)}(.*)/s);

    unless ($scheme && $settings) {
        croak "An RFC 2307 compliant string must be passed to matches()";
    }

    if ($scheme eq 'CRYPT'){
        given ($settings) {
            when (/^\$2(?:a|x|y)\$/)     {
                $scheme = 'Bcrypt';
                $settings =~ m{\A\$(2a|2x|2y)\$([0-9]{2})\$([./A-Za-z0-9]{22})}x;

                ($self->{type}, $self->{cost}, $self->{salt}) = ($1, $2, _de_bcrypt_base64($3));
            }
            default { croak "Unknown CRYPT format: $_"; }
        }
    }

    my $scheme_meta = {
        'MD5'     => { algorithm => 'MD5',     octets => 128 / 8 },
        'SMD5'    => { algorithm => 'MD5',     octets => 128 / 8 },
        'SHA'     => { algorithm => 'SHA-1',   octets => 160 / 8 },
        'SSHA'    => { algorithm => 'SHA-1',   octets => 160 / 8 },
        'SHA224'  => { algorithm => 'SHA-224', octets => 224 / 8 },
        'SSHA224' => { algorithm => 'SHA-224', octets => 224 / 8 },
        'SHA256'  => { algorithm => 'SHA-256', octets => 256 / 8 },
        'SSHA256' => { algorithm => 'SHA-256', octets => 256 / 8 },
        'SHA384'  => { algorithm => 'SHA-384', octets => 384 / 8 },
        'SSHA384' => { algorithm => 'SHA-384', octets => 384 / 8 },
        'SHA512'  => { algorithm => 'SHA-512', octets => 512 / 8 },
        'SSHA512' => { algorithm => 'SHA-512', octets => 512 / 8 },
        'Bcrypt'  => { algorithm => 'Bcrypt',  octets => 128 / 8 },
    };

    $self->{scheme}    = $scheme;
    $self->{algorithm} = $scheme_meta->{$scheme}->{algorithm};

    if (!defined $self->{salt}) {
        $self->{salt} = substr(decode_base64($settings), $scheme_meta->{$scheme}->{octets});
    }

    return $self;
}


# Gets the settings from config.yml, and merges them with any custom
# settings given to the constructor
sub _get_settings {
    my ($self, $options) = @_;

    $self->{algorithm} = $options->{algorithm} ||
                         plugin_setting->{algorithm} ||
                         'Bcrypt';

    my $plugin_setting = plugin_setting->{$self->algorithm};

    # Specify empty string to get an unsalted hash
    # Leaving it undefs results in 128 random bits being used as salt
    # bcrypt requires this amount, and is reasonable for other algorithms
    $self->{salt} = $options->{salt} //
                    $plugin_setting->{salt} //
                    rand_bits(128);

    # RFC 2307 scheme is based on the algorithm, with a prefixed 'S' for salted
    $self->{scheme} = join '', $self->algorithm =~ /[\w]+/g;
    $self->{scheme} = 'S'.$self->{scheme} if $self->{salt};

    given ($self->{scheme}) {
        when ('SHA1')    { $self->{scheme} = 'SHA';   }
        when ('SSHA1')   { $self->{scheme} = 'SSHA';  }
    }

    # Bcrypt requires a cost parameter
    if ($self->algorithm eq 'Bcrypt') {
        $self->{scheme} = 'CRYPT';
        $self->{type} = '2a';
        $self->{cost} = $options->{cost} ||
                        $plugin_setting->{cost} ||
                        4;

        $self->{cost} = 31 if $self->cost > 31;
        $self->{cost} = sprintf("%02d", $self->cost);
    }

    return $self;
}


# From Crypt::Eksblowfish::Bcrypt.
# Bcrypt uses it's own variation on base64
sub _en_bcrypt_base64 {
    my ($octets) = @_;
    my $text = encode_base64($octets, '');
    $text =~ tr{A-Za-z0-9+/=}{./A-Za-z0-9}d;
    return $text;
}


# And the decoder of bcrypt's custom base64
sub _de_bcrypt_base64 {
    my ($text) = @_;
    $text =~ tr{./A-Za-z0-9}{A-Za-z0-9+/};
    $text .= "=" x (3 - (length($text) + 3) % 4);
    return decode_base64($text);
}


register_plugin for_versions => [ 1, 2 ];

1;


=head1 MORE INFORMATION

=head2 Purpose

The aim of this module is to help you store new passwords in a secure manner, 
whilst still being able to verify and upgrade older passwords.

Cryptography is a vast and complex field. Many people try to roll their own 
methods for securing user data, but succeed only in coming up with 
a system that has little real security.

This plugin provides a simple way of managing that complexity, allowing 
developers to follow crypto best practice without having to become an expert.


=head2 Rationale

The module defaults to hashing passwords using the bcrypt algorithm, returning them
in RFC 2307 format.

RFC 2307 describes an encoding system for passphrase hashes, as used in the "userPassword"
attribute in LDAP databases. It encodes hashes as ASCII text, and supports several 
passphrase schemes by starting the encoding with an alphanumeric scheme identifier enclosed 
in braces.

RFC 2307 only specifies the C<MD5>, and C<SHA> schemes - however in real-world usage,
schemes that are salted are widely supported, and are thus provided by this module.

Bcrypt is an adaptive hashing algorithm that is designed to resist brute 
force attacks by including a cost (aka work factor). This cost increases 
the computational effort it takes to compute the hash.

SHA and MD5 are designed to be fast, and modern machines compute a billion 
hashes a second. With computers getting faster every day, brute forcing 
SHA hashes is a very real problem that cannot be easily solved.

Increasing the cost of generating a bcrypt hash is a trivial way to make 
brute forcing ineffective. With a low cost setting, bcrypt is just as secure 
as a more traditional SHA+salt scheme, and just as fast. Increasing the cost
as computers become more powerful keeps you one step ahead

For a more detailed description of why bcrypt is preferred, see this article: 
L<http://codahale.com/how-to-safely-store-a-password/>


=head2 Configuration

In your applications config file, you can set the default hashing algorithm,
and the default settings for every supported algorithm. Calls to
L<generate()|/"passphrase__generate"> will use the default settings
for that algorithm specified in here.

You can override these defaults when you call L<generate()|/"passphrase__generate">.

If you do no configuration at all, the default is to bcrypt with a cost of 4, and 
a strong psuedo-random salt.

    plugins:
        Passphrase:
            default: Bcrypt

            Bcrypt:
                cost: 8


=head2 Storage in a database

You should be storing the RFC 2307 string in your database, it's the easiest way
to use this module. You could store the C<raw_salt>, C<raw_hash>, and C<scheme>
separately, but this strongly discouraged. RFC 2307 strings are specifically
designed for storing hashed passwords, and should be used wherever possible.

The length of the string produced by L<generate()|/"passphrase__generate"> can
vary dependent on your settings. Below is a table of the lengths generated
using default settings.

You will need to make sure your database columns are at least this long.
If the string gets truncated, the password can I<never> be validated.

    ALGORITHM   LENGTH  EXAMPLE RFC 2307 STRING
    
    Bcrypt      68      {CRYPT}$2a$04$MjkMhQxasFQod1qq56DXCOvWu6YTWk9X.EZGnmSSIbbtyEBIAixbS
    SHA-512     118     {SSHA512}lZG4dZ5EU6dPEbJ1kBPPzEcupFloFSIJjiXCwMVxJXOy/x5qhBA5XH8FiUWj7u59onQxa97xYdqje/fwY5TDUcW1Urplf3KHMo9NO8KO47o=
    SHA-384     98      {SSHA384}SqZF5YYyk4NdjIM8YgQVfRieXDxNG0dKH4XBcM40Eblm+ribCzdyf0JV7i2xJvVHZsFSQNcuZPKtiTMzDyOU+w==
    SHA-256     74      {SSHA256}xsJHNzPlNCpOZ41OkTfQOU35ZY+nRyZFaM8lHg5U2pc0xT3DKNlGW2UTY0NPYsxU
    SHA-224     70      {SSHA224}FTHNkvKOdyX1d6f45iKLVxpaXZiHel8pfilUT1dIZ5u+WIUyhDGxLnx72X0=
    SHA-1       55      {SSHA}Qsaao/Xi/bYTRMQnpHuD3y5nj02wbdcw5Cek2y2nLs3pIlPh
    MD5         51      {SMD5}bgfLiUQWgzUm36+nBhFx62bi0xdwTp+UpEeNKDxSLfM=

=head2 Common Mistakes

Common mistakes people make when creating their own solution. If any of these 
seem familiar, you should probably be using this module

=over

=item Passwords are stored as plain text for a reason

There is never a valid reason to store a password as plain text.
Passwords should be reset and not emailed to customers when they forget.
Support people should be able to login as a user without knowing the users password.
No-one except the user should know the password - that is the point of authentication.

=item No-one will ever guess our super secret algorithm!

Unless you're a cryptography expert with many years spent studying 
super-complex maths, your algorithm is almost certainly not as secure 
as you think. Just because it's hard for you to break doesn't mean
it's difficult for a computer.

=item Our application-wide salt is "Sup3r_S3cret_L0ng_Word" - No-one will ever guess that.

This is common misunderstanding of what a salt is meant to do. The purpose of a 
salt is to make sure the same password doesn't always generate the same hash.
A fresh salt needs to be created each time you hash a password. It isn't meant 
to be a secret key.

=item We generate our random salt using C<rand>.

C<rand> isn't actually random, it's a non-unform pseudo-random number generator, 
and not suitable for cryptographic applications. Whilst this module also defaults to 
a PRNG, it is better than the one provided by C<rand>. Using a true RNG is a config
option away, but is not the default as it it could potentially block output if the
system does not have enough entropy to generate a truly random number

=item We use C<md5(pass.salt)>, and the salt is from C</dev/random>

MD5 has been broken for many years. Commodity hardware can find a 
hash collision in seconds, meaning an attacker can easily generate 
the correct MD5 hash without using the correct password.

=item We use C<sha(pass.salt)>, and the salt is from C</dev/random>

SHA isn't quite as broken as MD5, but it shares the same theoretical 
weaknesses. Even without hash collisions, it is vulnerable to brute forcing.
Modern hardware is so powerful it can try around a billion hashes a second. 
That means every 7 chracter password in the range [A-Za-z0-9] can be cracked 
in one hour on your average desktop computer.

=item If the only way to break the hash is to brute-force it, it's secure enough

It is unlikely that your database will be hacked and your hashes brute forced.
However, in the event that it does happen, or SHA512 is broken, using this module
gives you an easy way to change to a different algorithm, while still allowing
you to validate old passphrases

=back


=head1 KNOWN ISSUES

If you see errors like this

    Wide character in subroutine entry

or

    Input must contain only octets

The C<MD5>, C<bcrypt>, and C<SHA> algorithms can't handle chracters with an ordinal
value above 255, producing errors like this if they encounter them.
It is not possible for this plugin to automagically work out the correct
encoding for a given string.

If you see errors like this, then you probably need to use the L<Encode> module
to encode your text as UTF-8 (or whatever encoding it is) before giving it 
to C<passphrase>.

Text encoding is a bag of hurt, and errors like this are probably indicitive
of deeper problems within your app's code.

You will save yourself a lot of trouble if you read up on the
L<Encode> module sooner rather than later.

For further reading on UTF-8, unicode, and text encoding in perl,
see L<http://training.perl.com/OSCON2011/index.html>


=head1 SEE ALSO

L<Dancer>, L<Digest>, L<Crypt::Eksblowfish::Bcrypt>, L<Dancer::Plugin::Bcrypt>


=head1 AUTHOR

James Aitken <jaitken@cpan.org>


=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by James Aitken.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
