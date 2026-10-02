package Test::Netdisco::MungerProbe;

# Loaded only if a munger allowlist lets a class outside SNMP::Info through,
# so xt/87 can assert absence from %INC rather than absence of an effect.

use strict;
use warnings;

sub probe { return 'PROBE CALLED' }

1;
