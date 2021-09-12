package App::Netdisco::Util::Worker;

use Dancer ':syntax';
use App::Netdisco::JobQueue 'jq_insert';

use Encode 'encode';
use MIME::Base64 'encode_base64';

use Storable 'dclone';
use Data::Visitor::Tiny;

use base 'Exporter';
our @EXPORT = ('queue_hook');

sub queue_hook {
  my ($hook, $conf) = @_;
  my $extra = { action_conf => dclone ($conf->{'with'} || {}),
                event_data  => dclone (vars->{'hook_data'} || {}) };

  # remove scalar references which to_json cannot handle
  visit( $extra->{'event_data'}, sub {
    my ($key, $valueref) = @_;
    $$valueref = '' if ref $$valueref eq 'SCALAR';
  });

  jq_insert({
    action => ('hook::'. lc($conf->{'type'})),
    extra  => encode_base64( encode('UTF-8', to_json( $extra )) ),
  });

  return 1;
}

true;
