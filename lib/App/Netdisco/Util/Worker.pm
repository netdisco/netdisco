package App::Netdisco::Util::Worker;

use Dancer ':syntax';
use App::Netdisco::JobQueue 'jq_insert';

use MIME::Base64 'encode_base64';
use Data::Visitor::Tiny;
use Storable 'dclone';
use Encode 'encode';

use base 'Exporter';
our @EXPORT = ('queue_hooks');

sub queue_hooks {
  my @hooks = @_;
  return 0 unless scalar @hooks
    and scalar @{ setting('hooks') } and vars->{'hook_data'};

  my $count = 0;
  my $hooks = join '|', @hooks;

  foreach my $conf (@{ setting('hooks') }) {
    my $extra = { action_conf => dclone ($conf->{'with'} || {}),
                  event_data  => dclone (vars->{'hook_data'} || {}) };

    # remove scalar references which to_json cannot handle
    visit( $extra->{'event_data'}, sub {
      my ($key, $valueref) = @_;
      $$valueref = '' if ref $$valueref eq 'SCALAR';
    });

    if (scalar grep {$_ =~ m/^(?:${hooks})/} @{ $conf->{'events'} }) {
      jq_insert({
        action => ('hook::'. lc($conf->{'type'})),
        extra  => encode_base64( encode('UTF-8', to_json( $extra )) ),
      });
      ++$count;
    }
  }

  return $count;
}

true;
