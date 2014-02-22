package App::Netdisco::Web::Password;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Passphrase;

use Digest::MD5 ();

sub _make_password {
  my $pass = (shift || passphrase->generate_random);
  if (setting('safe_password_store')) {
      return passphrase($pass)->generate;
  }
  else {
      return Digest::MD5::md5_hex($pass),
  }
}

sub _bail {
    var('passchange_failed' => 1);
    return template 'password.tt';
}

any ['get', 'post'] => '/password' => require_login sub {
    my $old = param('old');
    my $new = param('new');
    my $confirm = param('confirm');

    if (request->is_post) {
        unless ($old and $new and $confirm and ($new eq $confirm)) {
            return _bail();
        }

        my ($success, $realm) = authenticate_user(
            session('logged_in_user'), $old
        );
        return _bail() if not $success;

        my $user = schema('netdisco')->resultset('User')
          ->find({username => session('logged_in_user')});
        return _bail() if not $user;

        $user->update({password => _make_password($new)});
        var('passchange_ok' => 1);
    }

    template 'password.tt';
};

true;
