package App::Netdisco::Util::API;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';

use List::MoreUtils 'singleton';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  resultsource_to_openapi_params
  parse_search_params
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

sub resultsource_to_openapi_params {
  my $sourcename = shift or return ();
  my @params = ();

  my $rs = schema('netdisco')->source($sourcename) or return ();
  my $columns = $rs->columns_info;

  foreach my $col ($rs->primary_columns,
                   (singleton ($rs->primary_columns, keys %{ $columns }))) {

    my $data = $columns->{$col};
    next if $data->{extra}->{hide_from_api};

    push @params, (
      $col => {
        description => $data->{extra}->{descr},
        type => ($data->{data_type} =~ m/int/    ? 'integer' :
                 $data->{data_type} eq 'boolean' ? 'boolean' : 'string'),
      }
    );
  }

  return @params;
}

sub parse_search_params {
  my $sourcename = shift or return {};
  my $params = shift or return {};
  my @pspec = resultsource_to_openapi_params($sourcename) or return {};

  my $partial = $params->{partial} || false;
  my $search = {};

  foreach my $param (@pspec) {
    next unless exists $params->{$param};

    if ($partial) {
      $search->{'text('. quotemeta($param) .')'}
        = { -ilike => '%'. $params->{$param} .'%'};
    }
    else {
      $search->{$param} = $params->{$param};
    }
  }

  return $search;
}

true;
