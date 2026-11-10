package App::Netdisco::Web::Plugin::Report::L3Domains;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'IP',
        tag          => 'l3domains',
        label        => 'L3 Domains',
        provides_csv => 1,
        api_endpoint => 1,
        api_parameters => [
          domain => {
            description => 'Comma-separated L3 domain ids whose member devices and VRFs to list',
          },
        ],
    }
);

# names repeat across domains, so a domain is chosen by id; 0 is the default
# table and has no members
sub domain_ids {
    my $param = shift;
    my @given = map { split /,/ } grep { defined } ( ref [] eq ref $param ? @$param : ($param) );
    my %seen;
    return [ grep { not $seen{$_}++ }
             map  { 0 + $_ }
             grep { /^\s*[1-9][0-9]{0,8}\s*$/ } @given ];
}

# the reportLink renderer sends "blank" for a row with no domain, so a "not
# grouped" link asks for the VRFs that have no member row
sub wants_ungrouped {
    my $param = shift;
    my @given = map { split /,/ } grep { defined } ( ref [] eq ref $param ? @$param : ($param) );
    return scalar grep { /^\s*blank\s*$/ } @given;
}

sub domain_lookup {
    return { map { ($_ => 1) } @{ domain_ids(shift) } };
}

# the page loads its content by submitting the sidebar form, so ?domain= has to
# arrive as selected options of the form's select
hook 'before_template' => sub {
    my $tokens = shift;
    my $page = uri_for('/report/l3domains')->path;
    my $content = uri_for('/ajax/content/report/l3domains')->path;
    return unless request->path eq $page or index(request->path, $content) == 0;

    $tokens->{l3domain_lkp} = domain_lookup( param('domain') );
    $tokens->{l3domain_list} = [ _summary() ] if request->path eq $page;
};

sub _summary {
    return schema(vars->{'tenant'})->resultset('L3Domain')->search(
        { 'me.id' => { '!=' => 0 } },
        {   join   => 'members',
            select => [
                'me.id',
                'me.name',
                \q{CASE WHEN me.inferred_name LIKE 'manual:%' THEN 'set by vrf_domains' ELSE min(members.reason) END},
                \q{array_agg(DISTINCT members.vrf ORDER BY members.vrf)},
                { count => { distinct => 'members.ip' } },
            ],
            as       => [qw/ id name evidence vrfs devices /],
            group_by => [qw/ me.id me.name me.inferred_name /],
            having   => \q{count(members.ip) > 0},
            order_by => [qw/ me.name me.id /],
        }
    )->hri->all;
}

# every named VRF, placed in a domain or not, so the report can show why a VRF
# did not join the domain an operator expected
sub vrf_search {
    my ($ids, $ungrouped) = @_;
    my $where = { 'me.vrf' => { '!=' => '' } };
    if ($ungrouped and scalar @$ids) {
        $where->{-or} = [ { 'l3_member.domain_id' => { -in => $ids } }, { 'l3_member.domain_id' => undef } ];
    }
    elsif ($ungrouped) {
        $where->{'l3_member.domain_id'} = undef;
    }
    elsif (scalar @$ids) {
        $where->{'l3_member.domain_id'} = { -in => $ids };
    }
    return ( $where, {
        join   => [ 'device', { l3_member => 'domain' } ],
        select => [
            \q{host(me.ip)}, 'device.dns', 'device.name', 'me.vrf', 'l3_member.domain_id',
            \q{CASE WHEN domain.id IS NULL THEN 'not grouped' ELSE domain.name || ' (#' || domain.id || ')' END},
            \q{CASE WHEN l3_member.source = 'manual' THEN 'set by vrf_domains' ELSE l3_member.reason END},
            'me.rd', 'me.rt_import', 'me.rt_export', 'me.l3_isid',
        ],
        as       => [qw/ ip dns device_name vrf domain_id domain grouped_by rd rt_import rt_export l3_isid /],
        order_by => [qw/ domain.name domain.id me.ip me.vrf /],
    } );
}

get '/ajax/content/report/l3domains' => require_login sub {
    my @results = schema(vars->{'tenant'})->resultset('DeviceVrf')
        ->search( vrf_search( domain_ids( param('domain') ), wants_ungrouped( param('domain') ) ) )->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        template 'ajax/report/l3domains.tt', { results => to_json(\@results) }, { layout => 'noop' };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/l3domains_csv.tt', { results => \@results }, { layout => 'noop' };
    }
};

true;
