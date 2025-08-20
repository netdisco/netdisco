package App::Netdisco::Web::GenericReport;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use Path::Class 'file';
use Storable 'dclone';
use Safe;

use HTML::Entities 'encode_entities';
use Regexp::Common qw( RE_net_IPv4 RE_net_IPv6 RE_net_MAC RE_net_domain );
use Regexp::Common::net::CIDR ();

our ($config, @data);

foreach my $report (@{setting('reports')}) {
  my $r = $report->{tag};

  register_report({
    tag => $r,
    label => $report->{label},
    category => ($report->{category} || 'My Reports'),
    ($report->{hidden} ? (hidden => true) : ()),
    provides_csv => true,
    api_endpoint => true,
    bind_params  => [ map {ref $_ ? $_->{param} : $_} @{ $report->{bind_params} } ],
    api_parameters => $report->{api_parameters},
  });

  get "/ajax/content/report/$r" => require_login sub {
      # TODO: this should be done by creating a new Virtual Result class on
      # the fly (package...) and then calling DBIC register_class on it.

      my $schema = ($report->{database} || vars->{'tenant'});
      my $rs = schema($schema)->resultset('Virtual::GenericReport')->result_source;
      (my $query = $report->{query}) =~ s/;$//;

      # unpick the rather hairy config of 'columns' to get field,
      # displayname, and "_"-prefixed options
      my %column_config = ();
      my @column_order  = ();
      foreach my $col (@{ $report->{columns} }) {
        foreach my $k (keys %$col) {
          if ($k !~ m/^_/) {
            push @column_order, $k;
            $column_config{$k} = dclone($col || {});
            $column_config{$k}->{displayname} = delete $column_config{$k}->{$k};
          }
        }
      }

      $rs->view_definition($query);
      $rs->remove_columns($rs->columns);
      $rs->add_columns( exists $report->{query_columns}
        ? @{ $report->{query_columns} } : @column_order
      );

      my $set = schema($schema)->resultset('Virtual::GenericReport')
        ->search(undef, {
          result_class => 'DBIx::Class::ResultClass::HashRefInflator',
          ( (exists $report->{bind_params})
            ? (bind => [map { param($_) } map {ref $_ ? $_->{param} : $_} @{ $report->{bind_params} }]) : () ),
        });
      @data = $set->all;

      # Data Munging support...

      my $compartment = Safe->new;
      $config = $report; # closure for the config of this report
      $compartment->share(qw/$config @data/);
      $compartment->permit_only(qw/:default sort/);

      my $munger  = file(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'site_plugins', $r)->stringify;
      my @results = ((-f $munger) ? $compartment->rdo( $munger ) : @data);
      return if $@ or (0 == scalar @results);

      if (request->is_ajax) {
          # searchable field support..

          my $recidr4 = $RE{net}{CIDR}{IPv4}{-keep}; #RE_net_CIDR_IPv4(-keep);
          my $rev4 = RE_net_IPv4(-keep);
          my $rev6 = RE_net_IPv6(-keep);
          my $remac = RE_net_MAC(-keep);

          foreach my $row (@results) {
              foreach my $col (@column_order) {
                  next unless $column_config{$col}->{_searchable};
                  my $fields = (ref $row->{$col} ? $row->{$col} : [$row->{$col}]);

                  foreach my $f (@$fields) {

                      encode_entities($f);

                      $f =~ s!\b${recidr4}\b!'<a href="'.
                        uri_for('/search', {q => "$1/$2"})->path_query
                        .qq{">$1/$2</a>}!gex;

                      if (not $1 and not $2) {
                          $f =~ s!\b${rev4}\b!'<a href="'.
                            uri_for('/search', {q => $1})->path_query .qq{">$1</a>}!gex;
                      }

                      $f =~ s!\b${rev6}\b!'<a href="'.
                        uri_for('/search', {q => $1})->path_query .qq{">$1</a>}!gex;

                      $f =~ s!\b${remac}\b!'<a href="'.
                        uri_for('/search', {q => $1})->path_query .qq{">$1</a>}!gex;

                      $row->{$col} = $f if not ref $row->{$col};
                  }
              }
          }

          template 'ajax/report/generic_report.tt',
              { results => \@results,
                is_custom_report => true,
                column_options => \%column_config,
                headings => [map {$column_config{$_}->{displayname}} @column_order],
                columns => [@column_order] }, { layout => 'noop' };
      }
      else {
          header( 'Content-Type' => 'text/comma-separated-values' );
          template 'ajax/report/generic_report_csv.tt',
              { results => \@results,
                headings => [map {$column_config{$_}->{displayname}} @column_order],
                columns => [@column_order] }, { layout => 'noop' };
      }
  };
}

true;
