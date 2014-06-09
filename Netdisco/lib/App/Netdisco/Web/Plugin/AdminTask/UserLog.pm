package App::Netdisco::Web::Plugin::AdminTask::UserLog;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use App::Netdisco::Util::ExpandParams 'expand_hash';

use App::Netdisco::Web::Plugin;

register_admin_task(
    {   tag   => 'userlog',
        label => 'User Activity Log',
    }
);

ajax '/ajax/control/admin/userlog/data' => require_role admin => sub {
    send_error( 'Missing parameter', 400 )
        unless ( param('draw') && param('draw') =~ /\d+/ );

    my $rs = schema('netdisco')->resultset('UserLog');

    my $exp_params = expand_hash( scalar params );

    my $recordsTotal = $rs->count;

    my @data = $rs->get_datatables_data($exp_params)->hri->all;

    my $recordsFiltered = $rs->get_datatables_filtered_count($exp_params);

    content_type 'application/json';
    return to_json(
        {   draw            => int( param('draw') ),
            recordsTotal    => int($recordsTotal),
            recordsFiltered => int($recordsFiltered),
            data            => \@data,
        }
    );
};

ajax '/ajax/control/admin/userlog/del' => require_role admin => sub {
    send_error( 'Missing entry', 400 ) unless param('entry');

    schema('netdisco')->txn_do(
        sub {
            my $device = schema('netdisco')->resultset('UserLog')
                ->search( { entry => param('entry') } )->delete;
        }
    );
};

ajax '/ajax/control/admin/userlog/delall' => require_role admin => sub {
    schema('netdisco')->txn_do(
        sub {
            my $device = schema('netdisco')->resultset('UserLog')->delete;
        }
    );
};

ajax '/ajax/content/admin/userlog' => require_role admin => sub {

    content_type('text/html');
    template 'ajax/admintask/userlog.tt', {}, { layout => undef };
};

1;
