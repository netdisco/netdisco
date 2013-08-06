package App::Netdisco::Web::Auth::Provider::DBIC;

use strict;
use warnings FATAL => 'all';

use base 'Dancer::Plugin::Auth::Extensible::Provider::Base';

# with thanks to yanick's patch at
# https://github.com/bigpresh/Dancer-Plugin-Auth-Extensible/pull/24

use Dancer qw(:syntax);
use Dancer::Plugin::DBIC;

use Digest::MD5;

sub authenticate_user {
    my ($self, $username, $password) = @_;
    return unless defined $username;

    my $user = $self->get_user_details($username) or return;
    return $self->match_password($password, $user);
}

sub match_password {
    my( $self, $password, $user ) = @_;
    return unless $user and $password and $user->password;

    my $settings = $self->realm_settings;
    my $password_column = $settings->{users_password_column} || 'password';
    
    my $sum = Digest::MD5::md5_hex($password);
    return ($sum eq $user->$password_column ? 1 : 0);
}


sub get_user_details {
    my ($self, $username) = @_;

    my $settings = $self->realm_settings;
    my $database = schema($settings->{schema_name})
        or die "No database connection";

    my $users_table     = $settings->{users_resultset}       || 'User';
    my $username_column = $settings->{users_username_column} || 'username';

    my $user = $database->resultset($users_table)->find({
        $username_column => $username
    }) or debug("No such user $username");

    return $user;
}

sub get_user_roles {
    my ($self, $username) = @_;
    return unless defined $username;

    my $settings = $self->realm_settings;
    my $database = schema($settings->{schema_name})
        or die "No database connection";

    # Get details of the user first; both to check they exist, and so we have
    # their ID to use.
    my $user = $self->get_user_details($username)
        or return;

    my $roles       = $settings->{roles_relationship} || 'roles';
    my $role_column = $settings->{role_column}        || 'role';

    return [ $user->$roles->get_column( $role_column )->all ];
}

1;
