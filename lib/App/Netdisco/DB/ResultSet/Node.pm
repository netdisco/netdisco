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

=head2 with_port_context

 my $set = $rs->search(...)->with_port_context;

Adds columns describing the switch port of each Node, so that API clients can
tell access ports from transit ports (uplinks, LAGs) without fetching the
ports of every switch:

=over 4

=item *

C<port_is_uplink>, C<port_remote_ip>, C<port_is_master>, C<port_slave_of>
from C<device_port>, and C<port_remote_is_wap>, C<port_remote_is_phone> from
C<device_port_properties>.

=item *

C<lag_remote_ip> is a member's C<remote_ip> for a LAG master, or the
master's for a LAG member.

=item *

C<neighbor_is_device> is true when the port's remote IP, or one of its LAG
members', is a known device address.

=item *

C<port_mac_count> is the number of distinct active MACs on the port, across
all VLANs.

=back

The columns use correlated subqueries per row, so callers should make this
opt-in for searches that can return many rows.

=cut

sub with_port_context {
    my $rs = shift;
    return $rs->search(undef, {
        '+columns' => [
          { port_is_uplink       => 'device_port.is_uplink' },
          { port_remote_ip       => 'device_port.remote_ip' },
          { port_is_master       => 'device_port.is_master' },
          { port_slave_of        => 'device_port.slave_of' },
          { port_remote_is_wap   => 'properties.remote_is_wap' },
          { port_remote_is_phone => 'properties.remote_is_phone' },
          # LLDP is usually on the members, not the master, and nodes on
          # members get moved to the master by macsuck
          { lag_remote_ip => \q{COALESCE(
              (SELECT agg.remote_ip FROM device_port agg
                WHERE agg.ip = me.switch AND agg.port = device_port.slave_of),
              (SELECT mem.remote_ip FROM device_port mem
                WHERE mem.ip = me.switch AND mem.slave_of = me.port
                  AND mem.remote_ip IS NOT NULL
                ORDER BY mem.port LIMIT 1))} },
          { neighbor_is_device => \q{EXISTS(
              SELECT 1 FROM device_ip di WHERE di.alias = device_port.remote_ip
                OR di.alias IN (SELECT mem.remote_ip FROM device_port mem
                                 WHERE mem.ip = me.switch AND mem.slave_of = me.port))} },
          { port_mac_count => \q{(SELECT count(DISTINCT pn.mac) FROM node pn
              WHERE pn.switch = me.switch AND pn.port = me.port AND pn.active)} },
        ],
        join => { device_port => 'properties' },
    });
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
      # only the rows in this set; the same MAC on another switch stays
      $self->update({ active => \'false' });

      # a MAC's IP, NetBIOS, monitor and wireless rows belong to the host,
      # not to one switch, so they are left alone while it is active elsewhere
      my $active_elsewhere = $schema->resultset('Node')->search(
        { mac => { '-in' => $nodes->as_query }, active => 1 },
        { columns => 'mac' });
      my $host_gone = { mac => { '-in' => $nodes->except($active_elsewhere)->as_query } };

      $schema->resultset($_)->search($host_gone)->update({ active => \'false' })
        for qw/NodeIp NodeNbt NodeMonitor/;
      $schema->resultset('NodeWireless')->search($host_gone)->delete;

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
      # a MAC's other rows are only deleted when no node row outside this set,
      # active or archived, still has the MAC; node rows are compared on their
      # whole key, since the same port name exists on many switches
      my $columns = [qw/mac switch port vlan/];
      my $still_used = $schema->resultset('Node')
        ->search({ mac => { '-in' => $nodes->as_query } }, { columns => $columns })
        ->except($self->search_rs(undef, { columns => $columns }))
        ->search(undef, { columns => 'mac' });
      my $host_gone = { mac => { '-in' => $nodes->except($still_used)->as_query } };

      $schema->resultset($_)->search($host_gone)->delete
        for qw/NodeIp NodeNbt NodeMonitor NodeWireless/;

      # now let DBIC do its thing
      return $self->next::method();
  }
}

1;
