package App::Netdisco::Web::DatabaseViewer;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

use SQL::Translator;
use SQL::Translator::Netdisco::Quick;
use SQL::Translator::Netdisco::Utils;

our ($db_meta);

my $dbic = schema('netdisco');
my $sqlt = SQL::Translator->new(
    parser => 'SQL::Translator::Parser::DBIx::Class',
    parser_args => { dbic_schema => $dbic },
    filters => [
        ['Netdisco::StorageEngine::DBIC::ViewsAsTables', $dbic],
        ['Netdisco::StorageEngine::DBIC::Relationships', $dbic],
        ['Netdisco::StorageEngine::DBIC::ProxyColumns', $dbic],
        'Netdisco::ColumnsAndPKs',
        'Netdisco::DisplayName',
        'Netdisco::ExtJSxType',
        ['Netdisco::StorageEngine::DBIC::AccessorDisplayName', $dbic],
    ],
    producer => 'SQL::Translator::Producer::POD', # something cheap
) or die SQL::Translator->error;

$sqlt->translate() or die $sqlt->error; # throw result away
$db_meta = SQL::Translator::Netdisco::Quick->new( $sqlt->schema );

foreach my $t ( values %{ $db_meta->t } ) {
  (my $r = 'nd2_db_'. $t->name) =~ s/::/_/g;

  register_report({
    tag => $r,
    label => $t->extra('display_name'),
    category => 'My Reports',
    provides_csv => false,
    api_endpoint => false,
#    bind_params  => $report->{bind_params},
  });

  get "/ajax/content/report/$r" => require_login sub {
      my $rs = schema('netdisco')->resultset($t->extra('dbic_class'))->result_source;

      my $set = schema('netdisco')->resultset($t->extra('dbic_class'))
        ->search(undef, {
          result_class => 'DBIx::Class::ResultClass::HashRefInflator',
          rows => 10,
#          ( (exists $report->{bind_params})
#            ? (bind => [map { param($_) } @{ $report->{bind_params} }]) : () ),
        });
      my @data = $set->all;

      template 'ajax/report/generic_report.tt',
          { results => \@data,
            is_custom_report => true,
            headings => [map  { $t->f->{$_}->extra('display_name') }
                         grep { ! $t->f->{$_}->extra('is_reverse') } @{ $t->extra('fields') }],
            columns => [grep { ! $t->f->{$_}->extra('is_reverse') } @{ $t->extra('fields') } ] }, { layout => 'noop' };
  };
}

true;
