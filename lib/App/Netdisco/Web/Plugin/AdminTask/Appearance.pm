package App::Netdisco::Web::Plugin::AdminTask::Appearance;
use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::DBIC;
use App::Netdisco::Web::Plugin;
use App::Netdisco::Web::Plugin::AdminTask::Appearance::State;
use Crypt::URandom ();
use File::Spec;

register_admin_task({tag => 'appearance', label => 'Appearance'});

sub _file {
    return setting('appearance_settings_file') || File::Spec->catfile(
      $ENV{NETDISCO_HOME} || $ENV{HOME}, 'netdisco-appearance.json');
}
sub _read { App::Netdisco::Web::Plugin::AdminTask::Appearance::State::read_state(_file()); }
sub _csrf {
    my $token = session('appearance_csrf');
    unless ($token) {
        $token = unpack 'H*', Crypt::URandom::urandom(32);
        session appearance_csrf => $token;
    }
    return $token;
}

ajax '/ajax/content/admin/appearance' => require_role admin => sub {
    header 'Cache-Control' => 'no-store';
    return template 'ajax/admintask/appearance.tt', {
      classic_colors => _read(), appearance_csrf => _csrf(),
    }, {layout => undef};
};

ajax '/ajax/appearance' => require_login sub {
    header 'Cache-Control' => 'no-store';
    content_type 'application/json';
    return to_json({classic_colors => _read()});
};

ajax '/ajax/control/admin/appearance/save' => require_role setting('defanged_admin') => sub {
    send_error('Method not allowed', 405) unless request->method eq 'POST';
    my $token = session('appearance_csrf');
    send_error('Please reload Appearance and try again', 403)
      unless $token and defined param('csrf') and param('csrf') eq $token;
    my $classic = param('classic_colors');
    send_error('Invalid palette', 400)
      unless defined $classic and $classic =~ /\A[01]\z/;
    eval { App::Netdisco::Web::Plugin::AdminTask::Appearance::State::write_state(_file(), $classic); 1 }
      or do { error "Appearance save failed: $@"; send_error('Unable to save appearance settings', 500); };
    eval {
        schema(vars->{'tenant'})->resultset('UserLog')->create({
          username => session('logged_in_user'),
          userip => scalar eval {request->remote_address},
          event => 'Updated global appearance',
          details => ($classic ? 'Classic colors enabled' : 'Current colors enabled'),
        });
    };
    warning "Appearance activity log failed: $@" if $@;
    header 'Cache-Control' => 'no-store';
    content_type 'application/json';
    return to_json({classic_colors => 0 + $classic});
};
true;
