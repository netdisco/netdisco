package App::Netdisco::Util::NodeMonitor;

use App::Netdisco;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::DNS qw/hostname_from_ip ipv4_from_hostname/;

use base 'Exporter';
our @EXPORT_OK = qw/
  monitor
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

sub _email {
  my ($to, $subject, $body) = @_;
  my $domain = setting('domain_suffix') || 'localhost';
  $domain =~ s/^\.//;

  my $SENDMAIL = '/usr/sbin/sendmail';
  open (SENDMAIL, "| $SENDMAIL -t") or die "Can't open sendmail at $SENDMAIL.\n";
    print SENDMAIL "To: $to\n";
    print SENDMAIL "From: Netdisco <netdisco\@$domain>\n";
    print SENDMAIL "Subject: $subject\n\n";
    print SENDMAIL $body;
  close (SENDMAIL) or die "Can't send letter. $!\n";
}

sub monitor {
  my $monitor = schema('netdisco')->resultset('Virtual::NodeMonitor');

  while (my $entry = $monitor->next) {
      my $body = <<"end_body";
........ n e t d i s c o .........
  Node    : @{[$entry->mac]} (@{[$entry->why]})
  When    : @{[$entry->date]}
  Switch  : @{[$entry->name]} (@{[$entry->switch]})
  Port    : @{[$entry->port]} (@{[$entry->portname]})
  Location: @{[$entry->location]}

end_body

      _email(
        $entry->cc,
        "Saw mac @{[$entry->mac]} (@{[$entry->why]}) on @{[$entry->name]} @{[$entry->port]}",
        $body
      );
  }
}

1;
