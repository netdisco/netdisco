package App::Netdisco::DB::ResultSet::DevicePower;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

=head1 ADDITIONAL METHODS


=head2 with_poestats

This is a modifier for any C<search()> which will add the following
additional synthesized columns to the result set:

=over 4

=item poe_capable_ports

Count of ports which have the ability to supply PoE.

=item poe_powered_ports

Count of ports with PoE administratively disabled.

=item poe_disabled_ports

Count of ports which are delivering power.

=item poe_errored_ports

Count of ports either reporting a fault or in test mode.

=item poe_power_committed

Total power that has been negotiated and therefore committed on ports
actively supplying power.

=item poe_power_delivering

Total power as measured on ports actively supplying power.

=back

=cut

sub with_poestats {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        'columns' => {
          ip => \"DISTINCT ON (me.ip, me.module) me.ip",
          module => 'module',
          power => 'power::bigint',
          status => 'status',
          poe_capable_ports => \"COUNT(ports.port) OVER (PARTITION BY me.ip, me.module)",
          poe_powered_ports => \"SUM(CASE WHEN ports.status = 'deliveringPower' THEN 1 ELSE 0 END) OVER (PARTITION BY me.ip, me.module)",
          poe_disabled_ports => \"SUM(CASE WHEN ports.admin = 'false' THEN 1 ELSE 0 END) OVER (PARTITION BY me.ip, me.module)",
          poe_errored_ports => \"SUM(CASE WHEN ports.status ILIKE '%fault' THEN 1 ELSE 0 END) OVER (PARTITION BY me.ip, me.module)",
          poe_power_committed => \("SUM(CASE "
                . "WHEN ports.status = 'deliveringPower' AND ports.class = 'class0' THEN 15.4 "
                . "WHEN ports.status = 'deliveringPower' AND ports.class = 'class1' THEN 4.0 " 
                . "WHEN ports.status = 'deliveringPower' AND ports.class = 'class2' THEN 7.0 "
                . "WHEN ports.status = 'deliveringPower' AND ports.class = 'class3' THEN 15.4 "
                . "WHEN ports.status = 'deliveringPower' AND ports.class = 'class4' THEN 30.0 "
                . "WHEN ports.status = 'deliveringPower' AND ports.class IS NULL THEN 15.4 "
                . "ELSE 0 END) OVER (PARTITION BY me.ip, me.module)"),
          poe_power_delivering => \("SUM(CASE WHEN (ports.power IS NULL OR ports.power = '0') "
                . "THEN 0 ELSE round(ports.power/1000.0, 1) END) "
                . "OVER (PARTITION BY me.ip, me.module)")
        },
          join => 'ports'
      });
}

1;
