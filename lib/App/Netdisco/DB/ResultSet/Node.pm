package App::Netdisco::DB::ResultSet::Node;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

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
        NodeMonitor
        NodeWireless
        NodeNbt
      /) {
          $schema->resultset($set)->search(
            { mac => { '-in' => $nodes->as_query }},
          )->delete;
      }

      # for node_ip only delete if there are no longer
      # any nodes referencing the IP.

      my @mac_restrict_aq     = @{${ $nodes->as_query }};
      my @macport_restrict_aq = @{${ $nodes->search(undef, { '+columns' => 'port' })->as_query }};
      my $mac_restrict     = shift @mac_restrict_aq;
      my $macport_restrict = shift @macport_restrict_aq;

      my $deleted = $schema->storage->dbh_do(sub {
        my ($storage, $dbh, @extra) = @_;
        local $dbh->{TraceLevel} =
          ($ENV{DBIC_TRACE} ? '1|SQL' : $dbh->{TraceLevel});
        $dbh->do(<<SQL
DELETE FROM node_ip WHERE mac IN (
  SELECT mac FROM node_ip
    LEFT OUTER JOIN (
      SELECT mac, port FROM node
      EXCEPT ($macport_restrict)) exceptions
    USING (mac)
   WHERE node_ip.mac IN ($mac_restrict)
     AND exceptions.port IS NULL)
SQL
        , undef, (map {$_->[1]} (@macport_restrict_aq, @mac_restrict_aq)));
      });

      # now let DBIC do its thing
      return $self->next::method();
  }
}

1;
