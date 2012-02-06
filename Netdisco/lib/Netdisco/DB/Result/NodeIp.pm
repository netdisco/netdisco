use utf8;
package Netdisco::DB::Result::NodeIp;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("node_ip");
__PACKAGE__->add_columns(
  "mac",
  { data_type => "macaddr", is_nullable => 0 },
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
  "time_first",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
  "time_last",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
);
__PACKAGE__->set_primary_key("mac", "ip");


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:9+CuvuVWH88WxAf6IBij8g

# XXX uncomment the following two lines if you have a "dns" column XXX
# XXX in your node_ip table which caches the host's name           XXX
#__PACKAGE__->add_column("dns" =>
#  { data_type => "text", is_nullable => 1, accessor => undef });
# XXX ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ XXX

# some customize their node_ip table to have a dns column which
# is the cached record at the time of discovery
sub dns {
  my $row = shift;
  return $row->get_column('dns')
    if $row->result_source->has_column('dns');

  use Net::DNS ();
  my $q = Net::DNS::Resolver->new->query($row->ip);
  if ($q) {
    foreach my $rr ($q->answer) {
      next unless $rr->type eq 'PTR';
      return $rr->ptrdname;
    }
  }
  return undef;
}

__PACKAGE__->belongs_to( oui => 'Netdisco::DB::Result::Oui',
    sub {
        my $args = shift;
        return {
            "$args->{foreign_alias}.oui" =>
              { '=' => \"substring(cast($args->{self_alias}.mac as varchar) for 8)" }
        };
    },
    { join_type => 'LEFT' }
);

__PACKAGE__->has_many( node_ips => 'Netdisco::DB::Result::NodeIp',
  { 'foreign.mac' => 'self.mac' } );
__PACKAGE__->has_many( nodes => 'Netdisco::DB::Result::Node',
  { 'foreign.mac' => 'self.mac' } );

my $search_attr = {
    order_by => {'-desc' => 'time_last'},
    '+select' => [
      \"to_char(time_first, 'YYYY-MM-DD HH24:MI')",
      \"to_char(time_last, 'YYYY-MM-DD HH24:MI')",
    ],
    '+as' => [qw/ time_first_stamp time_last_stamp /],
};

sub ip_aliases {
    my ($row, $cond, $attrs) = @_;
    $cond ||= {};
    $attrs ||= {};

    my $rs = $row->node_ips({ip  => { '!=' => $row->ip }});
    $rs = $rs->search_rs({}, {'+columns' => 'dns'})
      if $rs->has_dns_col;

    return $rs
      ->search_rs({}, $search_attr)
      ->search($cond, $attrs);
}

sub node_sightings {
    my ($row, $cond, $attrs) = @_;
    $cond ||= {};
    $attrs ||= {};

    return $row
      ->nodes({}, {
        '+columns' => [qw/ device.dns /],
        join => 'device',
      })
      ->search_rs({}, $search_attr)
      ->search($cond, $attrs);
}

# accessors for custom formatted columns
sub time_first_stamp { return (shift)->get_column('time_first_stamp') }
sub time_last_stamp  { return (shift)->get_column('time_last_stamp')  }

1;
