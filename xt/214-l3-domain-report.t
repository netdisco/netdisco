#!/usr/bin/env perl

use strict;
use warnings;

# The L3 Domains report lists every named VRF of every device, with the domain
# it landed in, why, and the evidence it carries (RD, route targets, I-SID), so
# an operator can see why a VRF is in a domain or is not; ?domain=<ids> limits
# it to those domains.
# Domain names repeat (each is only the commonest VRF name inside it), so a
# domain is chosen by id. CI has no database: the id parsing is checked
# directly and the templates are rendered with fixed rows.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use App::Netdisco;
use Dancer ':syntax';
use App::Netdisco::Web::Plugin::Report::L3Domains;
use App::Netdisco::DB::Result::DeviceVrf;
use YAML::XS ();
use lib 'xt/lib';
use Test::Netdisco::Snapshot qw/render_template/;

sub report_html {
  my %stash = @_;
  return render_template('ajax/report/l3domains.tt', { uri_for => sub { $_[0] }, %stash });
}

subtest 'report__registered__in_ip_category' => sub {
  my $report = setting('_reports')->{l3domains};
  ok $report, 'registered under its tag';
  is $report->{category}, 'IP', 'IP category';
  is $report->{label}, 'L3 Domains', 'label';
  ok $report->{provides_csv}, 'provides CSV';
  ok $report->{api_endpoint}, 'API endpoint';
  # swagger_path empties api_parameters in place, so read the API document
  my $api = Dancer::Plugin::Swagger->instance->doc->{paths}{'/api/v1/report/ip/l3domains'}{get};
  is_deeply [ map { "$_->{in}:$_->{name}" } @{ $api->{parameters} || [] } ], ['query:domain'], 'domain is an API parameter';
  ok scalar(grep { $_ eq 'Report::L3Domains' }
    @{ YAML::XS::LoadFile('share/config.yml')->{web_plugins} }), 'enabled in web_plugins';
};

subtest 'domain_ids__param__positive_integers_only' => sub {
  my $ids = \&App::Netdisco::Web::Plugin::Report::L3Domains::domain_ids;
  is_deeply $ids->(undef), [], 'none given';
  is_deeply $ids->(''), [], 'empty';
  is_deeply $ids->('8'), [8], 'one id';
  is_deeply $ids->('1,8, 12'), [1, 8, 12], 'a comma list, spaces allowed';
  is_deeply $ids->(['3', '4,5']), [3, 4, 5], 'repeated parameter';
  is_deeply $ids->('1,x,,-3,0,2.5,7'), [1, 7], 'anything else is dropped, domain 0 included';
  is_deeply $ids->('8,8'), [8], 'each id once';
};

my @vrf_rows = (
  { ip => '172.20.20.93', dns => 'leaf3.lab.example', device_name => 'leaf3', vrf => 'blue', domain_id => 8,
    domain => 'blue (#8)', grouped_by => 'shared L3 I-SID 30002', rd => undef, rt_import => [], rt_export => [], l3_isid => 30002 },
  { ip => '172.20.20.191', dns => undef, device_name => 'r9', vrf => 'blue', domain_id => 1,
    domain => 'blue (#1)', grouped_by => 'same name blue', rd => '80:2', rt_import => ['65010:1'],
    rt_export => ['65010:1', '65010:2'], l3_isid => undef },
  { ip => '172.20.20.192', dns => undef, device_name => undef, vrf => 'blue', domain_id => undef,
    domain => 'not grouped', grouped_by => undef, rd => '80:3', rt_import => [], rt_export => [], l3_isid => undef },
);

sub json_block {
  my ($json) = shift =~ m{<script type="application/json" id="nd-results-report-l3domains">(.*?)</script>}s;
  return $json;
}

subtest 'template__vrf_rows__json_block_and_renderers' => sub {
  my ($html, $error) = report_html(results => to_json(\@vrf_rows));
  is $error, undef, 'renders';
  is from_json(json_block($html))->[2]{domain_id}, undef, 'a VRF in no domain travels too';
  is_deeply from_json(json_block($html))->[1]{rt_export}, ['65010:1', '65010:2'], 'rows travel as JSON';
  my ($table) = $html =~ m{data-nd-table='(.*?)'}s;
  my @cols = @{ from_json($table)->{columns} };
  is_deeply [ map { $_->{data} } @cols ], [qw/ip vrf domain grouped_by rd rt_import rt_export l3_isid/], 'column order';
  my %render = map { $_->{data} => $_->{render} } @cols;
  is_deeply $render{ip}, { name => 'deviceLink', tab => 'addresses',
    label => { dns => 'dns', name => 'device_name', ip => 'ip' } }, 'device link, house label';
  is_deeply $render{domain}, { name => 'reportLink', report => 'report_l3domains', param => 'domain',
    key => 'domain_id', show => 'domain' }, 'domain by id';
  is_deeply $render{rt_import}, { name => 'join', key => 'rt_import', with => ', ' }, 'import RTs joined';
  is_deeply $render{rt_export}, { name => 'join', key => 'rt_export', with => ', ' }, 'export RTs joined';
  is $render{$_}, 'escape', "$_ is text" for qw/vrf grouped_by rd l3_isid/;
  like $html, qr{"device":\s*"/device"}, 'device url';
  like $html, qr{"report_l3domains":\s*"/report/l3domains"}, 'report url';
  like $html, qr{<th>Why grouped</th>}, 'reason heading';
  unlike $html, qr{<tbody>}, 'no server-rendered rows';
};

subtest 'template__names_with_markup__cannot_close_the_json_block' => sub {
  my $hostile = '</script><b>R&D</b>';
  my ($html) = report_html(results => to_json([ { %{ $vrf_rows[0] }, vrf => $hostile, rd => $hostile,
    dns => $hostile, rt_import => [$hostile] } ]));
  unlike $html, qr{</script><b>}, 'no raw markup from device data';
  is from_json(json_block($html))->[0]{rd}, $hostile, 'carried intact';
};

# the report answers "why is this VRF in that domain, or not": every named VRF
# is listed, including one the recompute has not placed yet
subtest 'vrf_search__every_named_vrf__with_or_without_a_domain' => sub {
  my $search = \&App::Netdisco::Web::Plugin::Report::L3Domains::vrf_search;
  my ($where, $attrs) = $search->([]);
  is_deeply $where, { 'me.vrf' => { '!=' => '' } }, 'default table excluded, nothing else filtered';
  is_deeply $attrs->{join}, [ 'device', { l3_member => 'domain' } ], 'device, then its membership';
  my $rel = App::Netdisco::DB::Result::DeviceVrf->relationship_info('l3_member');
  is $rel->{attrs}{join_type}, 'LEFT', 'a VRF with no member row is kept';
  like ${ $attrs->{select}[ (grep { $attrs->{as}[$_] eq 'domain' } 0 .. $#{ $attrs->{as} })[0] ] },
    qr/'not grouped'/, 'and labeled not grouped';
  like ${ $attrs->{select}[ (grep { $attrs->{as}[$_] eq 'grouped_by' } 0 .. $#{ $attrs->{as} })[0] ] },
    qr/'set by vrf_domains'/, 'a manual member says so';
  my ($only) = $search->([7, 16]);
  is_deeply $only->{'l3_member.domain_id'}, { -in => [7, 16] }, 'filtered to the domains asked for';
};

# a "not grouped" link sends domain=blank, which domain_ids drops, so the link
# opened every named VRF instead of the ungrouped ones
subtest 'wants_ungrouped__blank_value__asks_for_vrfs_with_no_domain' => sub {
  my $wants = \&App::Netdisco::Web::Plugin::Report::L3Domains::wants_ungrouped;
  ok !$wants->(undef), 'none given';
  ok !$wants->('8'), 'an id only';
  ok $wants->('blank'), 'blank';
  ok $wants->(' blank '), 'blank with spaces';
  ok $wants->(['8', 'blank']), 'blank beside an id';
  ok $wants->('8,blank'), 'blank in a comma list';
};

subtest 'vrf_search__ungrouped__filters_to_no_member_row' => sub {
  my $search = \&App::Netdisco::Web::Plugin::Report::L3Domains::vrf_search;
  my ($alone) = $search->([], 1);
  ok exists $alone->{'l3_member.domain_id'}, 'domain_id filtered';
  is $alone->{'l3_member.domain_id'}, undef, 'to VRFs with no domain';
  my ($both) = $search->([7], 1);
  is_deeply $both->{-or}, [ { 'l3_member.domain_id' => { -in => [7] } }, { 'l3_member.domain_id' => undef } ],
    'with ids, either those domains or none';
  ok !exists $both->{'l3_member.domain_id'}, 'and no separate id filter';
};

subtest 'csv__vrf_rows__render' => sub {
  my ($csv, $error) = render_template('ajax/report/l3domains_csv.tt', { results => \@vrf_rows });
  is $error, undef, 'renders';
  like $csv, qr/^Device,"Device IP",VRF,Domain,"Why grouped",RD,"Import RTs","Export RTs",I-SID$/m, 'header';
  like $csv, qr/^172\.20\.20\.192,172\.20\.20\.192,blue,"not grouped",,80:3,,,$/m, 'a VRF in no domain, labeled by address';
  like $csv, qr/^r9,172\.20\.20\.191,blue,"blue \(#1\)","same name blue",80:2,65010:1,"65010:1,65010:2",$/m, 'row';
};

# the report page loads its content by submitting its sidebar form, so
# ?domain= reaches the content only through a field of that form
subtest 'sidebar__domains__selectable_by_id_labelled_with_evidence' => sub {
  my ($html, $error) = render_template('sidebar/report/l3domains.tt', {
    report => { tag => 'l3domains' },
    l3domain_list => [
      { id => 7, name => 'red', evidence => 'shared L3 I-SID 30001' },
      { id => 16, name => 'red', evidence => 'same name red' },
      { id => 2, name => '<b>x</b>', evidence => 'same name <b>x</b>' },
    ],
    l3domain_lkp => { 16 => 1 },
  });
  is $error, undef, 'renders';
  (my $flat = $html) =~ s/\s+/ /g;
  like $flat, qr{<select[^>]* multiple name="domain"}, 'a multi-select named domain';
  like $flat, qr{<option value="7">red \(shared L3 I-SID 30001\)</option>}, 'two domains of one name told apart';
  like $flat, qr{<option value="16" selected="selected">red \(same name red\)</option>}, 'the domains asked for are selected';
  like $flat, qr{&lt;b&gt;x&lt;/b&gt;}, 'escaped';
  unlike $flat, qr{<b>x</b>}, 'no raw markup';
};

subtest 'domain_lookup__param__selected_ids' => sub {
  my $lkp = \&App::Netdisco::Web::Plugin::Report::L3Domains::domain_lookup;
  is_deeply $lkp->('7,16'), { 7 => 1, 16 => 1 }, 'from a comma list';
  is_deeply $lkp->(['7', '16']), { 7 => 1, 16 => 1 }, 'from the select';
  is_deeply $lkp->(undef), {}, 'none';
};

done_testing;
