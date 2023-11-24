package App::Netdisco::Web::Plugin::Report::PortVLANMismatch;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use List::MoreUtils qw/listcmp sort_by/;

register_report(
    {   category => 'Port',
        tag      => 'portvlanmismatch',
        label    => 'Mismatched VLANs',
        provides_csv => 1,
        api_endpoint => 1,
    }
);

get '/ajax/content/report/portvlanmismatch' => require_login sub {
    return unless schema(vars->{'tenant'})->resultset('Device')->count;
    my @results = schema(vars->{'tenant'})
      ->resultset('Virtual::PortVLANMismatch')->search({},{
          bind => [ setting('sidebar_defaults')->{'device_ports'}->{'p_hide1002'}->{'default'}
                      ? (1002, 1003, 1004, 1005) : (0, 0, 0, 0) ],
      })
      ->hri->all;

#    # note that the generated list is rendered without HTML escape,
#    # so we MUST sanitise here with the grep
#    foreach my $res (@results) {
#        my @left  = grep {m/^(?:n:)?\d+$/} map {s/\s//g; $_} split ',', $res->{left_vlans};
#        my @right = grep {m/^(?:n:)?\d+$/} map {s/\s//g; $_} split ',', $res->{right_vlans};
#
#        my %new = (0 => [], 1 => []);
#        my %cmp = listcmp @left, @right;
#        foreach my $vlan (keys %cmp) {
#            map { push @{ $new{$_} }, ( (2 == scalar @{ $cmp{$vlan} }) ? $vlan : "<strong>$vlan</strong>" ) } @{ $cmp{$vlan} };
#        }
#
#        $res->{left_vlans}  = join ', ', sort_by { (my $a = $_) =~ s/\D//g; sprintf "%05d", $a } @{ $new{0} };
#        $res->{right_vlans} = join ', ', sort_by { (my $a = $_) =~ s/\D//g; sprintf "%05d", $a } @{ $new{1} };
#    }

    foreach my $res (@results) {
        $res->{only_left_vlans}  = join ', ', @{ $res->{only_left_vlans}  || [] };
        $res->{only_right_vlans} = join ', ', @{ $res->{only_right_vlans} || [] };
    }

    if (request->is_ajax) {
        my $json = to_json (\@results);
        template 'ajax/report/portvlanmismatch.tt', { results => $json }, { layout => 'noop' };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/portvlanmismatch_csv.tt', { results => \@results, }, { layout => 'noop' };
    }
};

1;
