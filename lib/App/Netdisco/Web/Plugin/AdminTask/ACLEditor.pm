package App::Netdisco::Web::Plugin::AdminTask::ACLEditor;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Ajax;

use App::Netdisco::Web::Plugin;

use MIME::Base64 'decode_base64';

register_admin_task({
    tag => "acleditor",
    label => "ACL Editor",
    hidden => true,
});

get '/ajax/content/admin/acleditor' => require_role admin => sub {
    my $acl_name = param('acl_name');
    send_error('Bad Request', 400) unless $acl_name;

    my $acl = schema(vars->{'tenant'})->resultset('AccessControlListName')
                                      ->find({acl_name => $acl_name});
    send_error('Bad Request', 400) unless $acl;

    my $maps = schema(vars->{'tenant'})->resultset('AccessControlListMap')
      ->search({acl_name => $acl_name}, { prefetch => [qw/left_acl_with_dns right_acl/],
                                          order_by => 'me.id' })
      or send_error('Bad Request', 400);

    template 'ajax/admintask/acleditor.tt', {
      acl_name => $acl->acl_name,
      results => $maps,
    }, { layout => undef };
};

post '/ajax/control/admin/acleditor/add' => require_role setting('defanged_admin') => sub {
    my $role = param("role_name");
    my $device_rule = param("device_rule");
    my $port_rule = param("port_rule");
    send_error('Bad Request', 400) unless $device_rule and $role;

    schema(vars->{'tenant'})->txn_do(sub {
      my $row = schema(vars->{'tenant'})->resultset('PortCtlRole')
        ->create({
          role_name => $role,
          device_acl => {}, port_acl => {},
        });

      $row->device_acl->update({
            rules => [ $device_rule ],
      });
      $row->port_acl->update({
            rules => [ $port_rule ],
      }) if $port_rule;
    });

    return '';
};

post '/ajax/control/admin/acleditor/delete' => require_role setting('defanged_admin') => sub {
    my $id = param("id");
    my $role = param("role_name");
    send_error('Bad Request', 400) unless $id and $role;
    
    schema(vars->{'tenant'})->txn_do(sub {
      my $row = schema(vars->{'tenant'})->resultset('PortCtlRole')
        ->find($id) or send_error('Bad Request', 400);

      schema(vars->{'tenant'})->resultset('AccessControlList')
        ->find($row->device_acl_id)->delete;
      schema(vars->{'tenant'})->resultset('AccessControlList')
        ->find($row->port_acl_id)->delete;

      $row->delete;

      if (schema(vars->{'tenant'})->resultset('PortCtlRole')
            ->search({ role_name => $role })->count() == 0) {
          # roles cannot be empty - delete from the Port Control Roles panel only
          my $new = schema(vars->{'tenant'})->resultset('PortCtlRole')
            ->create({
              role_name => $role,
              device_acl => {}, port_acl => {},
            });
          $new->device_acl->update({ rules => ['group:__ANY__'] });
      }
    });

    return '';
};

post '/ajax/control/admin/acleditor/update' => require_role setting('defanged_admin') => sub {
    my $id = param("id");
    my $role = param("role_name");
    send_error('Bad Request', 400) unless $id and $role;

    my @device_rules = map {decode_base64($_)}
                          @{ ref param('device_rule') ? param('device_rule')
                                                      : defined param('device_rule') ? [param('device_rule')]
                                                                                     : [] };
    @device_rules = ('group:__ANY__') if 0 == scalar @device_rules;

    my @port_rules   = map {decode_base64($_)}
                          @{ ref param('port_rule') ? param('port_rule')
                                                    : defined param('port_rule') ? [param('port_rule')]
                                                                                 : [] };

    schema(vars->{'tenant'})->txn_do(sub {
      my $row = schema(vars->{'tenant'})->resultset('PortCtlRole')
        ->find($id) or send_error('Bad Request', 400);

      schema(vars->{'tenant'})->resultset('AccessControlList')
        ->find($row->device_acl_id)->update({rules => \@device_rules });
      schema(vars->{'tenant'})->resultset('AccessControlList')
        ->find($row->port_acl_id)->update({rules => \@port_rules });
    });

    return '';
};

true;

