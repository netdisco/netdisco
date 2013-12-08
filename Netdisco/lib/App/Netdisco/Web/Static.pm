package App::Netdisco::Web::Static;

use Dancer ':syntax';
use Path::Class;

get '/plugin/*/*.js' => sub {
  my ($plugin) = splat;

  my $content = template
    'plugin.tt', { target => "plugin/$plugin/$plugin.js" },
    { layout => undef };

  send_file \$content,
    content_type => 'application/javascript',
    filename => "$plugin.js";
};

get '/plugin/*/*.css' => sub {
  my ($plugin) = splat;

  my $content = template
    'plugin.tt', { target => "plugin/$plugin/$plugin.css" },
    { layout => undef };

  send_file \$content,
    content_type => 'text/css',
    filename => "$plugin.css";
};

true;
