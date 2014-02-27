package App::Netdisco::Web::GenericReport;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

foreach my $r (keys %{setting('reports')}) {
  my $report = setting('reports')->{$r};

  register_report({
    tag => $r,
    label => $report->{label},
    category => $report->{category},
    provides_csv => true,
  });

  get "/ajax/content/report/$r" => require_login sub {
      my $rs = schema('netdisco')->resultset('Virtual::GenericReport')->result_source;

      # this should be done by creating a new Virtual Result class on the fly
      # (package...) and then calling DBIC register_class on it.
      $rs->view_definition($report->{query});
      $rs->remove_columns($rs->columns);
      $rs->add_columns(map {keys %{$_}} @{$report->{columns}});

      my $set = schema('netdisco')->resultset('Virtual::GenericReport');
      return unless $set->count;

      if (request->is_ajax) {
          template 'ajax/report/generic_report.tt',
              { results => $set,
                headings => [map {values %{$_}} @{$report->{columns}}],
                columns => [$rs->columns] },
              { layout => undef };
      }
      else {
          header( 'Content-Type' => 'text/comma-separated-values' );
          template 'ajax/report/generic_report_csv.tt',
              { results => $set,
                headings => [map {values %{$_}} @{$report->{columns}}],
                columns => [$rs->columns] },
              { layout => undef };
      }
  };
}

true;
