package App::Netdisco::DB::ResultSet::Node;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings FATAL => 'all';

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

=head1 ADDITIONAL METHODS

=head2 search_by_mac( \%cond, \%attrs? )

 my $set = $rs->search_by_mac({mac => '00:11:22:33:44:55', active => 1});

Like C<search()>, this returns a ResultSet of matching rows from the Node
table.

=over 4

=item *

The C<cond> parameter must be a hashref containing a key C<mac> with
the value to search for.

=item *

Results are ordered by time last seen.

=item *

Additional columns C<time_first_stamp> and C<time_last_stamp> provide
preformatted timestamps of the C<time_first> and C<time_last> fields.

=item *

A JOIN is performed on the Device table and the Device C<dns> column
prefetched.

=back

To limit results only to active nodes, set C<< {active => 1} >> in C<cond>.

=cut

sub search_by_mac {
    my ($rs, $cond, $attrs) = @_;

    die "mac address required for search_by_mac\n"
      if ref {} ne ref $cond or !exists $cond->{mac};

    $cond->{'me.mac'} = delete $cond->{mac};

    return $rs
      ->search_rs({}, {
        order_by => {'-desc' => 'time_last'},
        '+columns' => [
          'device.dns',
          { time_first_stamp => \"to_char(time_first, 'YYYY-MM-DD HH24:MI')" },
          { time_last_stamp =>  \"to_char(time_last, 'YYYY-MM-DD HH24:MI')" },
        ],
        join => 'device',
      })
      ->search($cond, $attrs);
}

=head1 SPECIAL METHODS

=head2 delete( \%options? )

Overrides the built-in L<DBIx::Class> delete method to more efficiently
handle the removal or archiving of nodes.

=cut

sub delete {
  my $self = shift;
  my ($opts) = @_;
  $opts = {} if (ref {} ne ref $opts);

  my $schema = $self->result_source->schema;
  my $nodes = $self->search(undef, { columns => 'mac' });

  if (exists $opts->{archive_nodes} and $opts->{archive_nodes}) {
      foreach my $set (qw/
        NodeIp
        NodeNbt
        NodeMonitor
        Node
      /) {
          $schema->resultset($set)->search(
            { mac => { '-in' => $nodes->as_query }},
          )->update({ active => \'false' });
      }

      $schema->resultset('NodeWireless')
        ->search({ mac => { '-in' => $nodes->as_query }})->delete;

      # avoid letting DBIC delete nodes
      return 0E0;
  }
  elsif (exists $opts->{only_nodes} and $opts->{only_nodes}) {
      # now let DBIC do its thing
      return $self->next::method();
  }
  elsif (exists $opts->{keep_nodes} and $opts->{keep_nodes}) {
      # avoid letting DBIC delete nodes
      return 0E0;
  }
  else {
      foreach my $set (qw/
        NodeIp
        NodeNbt
        NodeMonitor
        NodeWireless
      /) {
          $schema->resultset($set)->search(
            { mac => { '-in' => $nodes->as_query }},
          )->delete;
      }

      # now let DBIC do its thing
      return $self->next::method();
  }
}

=head2 with_multi_ips_as_hashref

This is a modifier for C<search()> which returns a list of hash references
for nodes within the search criteria with multiple IP addresses.  Each hash
reference contains the keys:

=over 4

=item mac

Node MAC address.

=item switch

IP address of the device where the node is attached.

=item port

Port on the device where the node is attached.

=item dns

DNS name of the device where the node is attached.

=item name

C<sysName> of the device where the node is attached.

=item ip_count

Count of IP addresses associated with the node.

=item vendor

Vendor string based upon the node OUI.

=back

=cut

sub with_multi_ips_as_hashref {
  my ( $rs, $cond, $attrs ) = @_;

  my @return = $rs->search(
    {},
    { result_class => 'DBIx::Class::ResultClass::HashRefInflator',
      select       => [ 'mac', 'switch', 'port' ],
      join         => [qw/device ips oui/],
      '+columns'   => [
        { 'dns'      => 'device.dns' },
        { 'name'     => 'device.name' },
        { 'ip_count' => { count => 'ips.ip' } },
        { 'vendor'   => 'oui.company' }
      ],
      group_by =>
        [qw/ me.mac me.switch me.port device.dns device.name oui.company/],
      having => \[ 'count(ips.ip) > ?', [ count => 1 ] ],
      order_by => { -desc => [qw/count/] },
    }
  )->all;

  return \@return;
}

1;
