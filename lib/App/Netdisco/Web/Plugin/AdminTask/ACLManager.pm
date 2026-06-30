package App::Netdisco::Web::Plugin::AdminTask::ACLManager;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Ajax;

use App::Netdisco::Web::Plugin;

register_admin_task({
    tag => "aclmanager",
    label => "Access Control Lists"
});

ajax '/ajax/content/admin/aclmanager' => require_role admin => sub {
    my @acls = schema(vars->{'tenant'})->resultset('AccessControlListName')
                                       ->order_by([qw/acl_type acl_name/])->all;

    template 'ajax/admintask/aclmanager.tt', {
      results => \@acls,
    }, { layout => undef };
};

ajax '/ajax/control/admin/aclmanager/add' => require_role setting('defanged_admin') => sub {
    my $acl = param('acl_name');
    send_error('Bad Request', 400) unless $acl;
    my $type = param('acl_type');
    send_error('Bad Request', 400) unless $type
      and $type =~ m/^(?:host|host_host|host_port)$/;
    send_error('Bad Request', 400)
      if schema(vars->{'tenant'})->resultset('AccessControlListName')
                                 ->search({acl_name => $acl})->count();

    schema(vars->{'tenant'})->txn_do(sub {
      schema(vars->{'tenant'})->resultset('AccessControlListName')
        ->create({
          acl_name => $acl,
          acl_type => $type,
        });

      my $new = schema(vars->{'tenant'})->resultset('AccessControlListMap')
        ->create({
          acl_name => $acl,
          left_acl => {}, right_acl => {},
        });

      $new->left_acl->update({ rules => ['group:__ANY__'] });
      $new->right_acl->update({ rules => ['group:__ANY__'] })
        if $type eq 'host_host';
    });

    return '';
};

ajax '/ajax/control/admin/aclmanager/delete' => require_role setting('defanged_admin') => sub {
    my $acl = param('acl_name');
    send_error('Bad Request', 400) unless $acl;

    schema('netdisco')->resultset('User')
      ->search({portctl_role => $acl})
      ->update({
        ((exists config->{'portctl_by_role_shadow'}->{$acl})
          ? () : (portctl_role => undef, port_control => \'false')),
      });

    schema(vars->{'tenant'})->txn_do(sub {
      schema(vars->{'tenant'})->resultset('AccessControlListName')
                              ->find({ acl_name => $acl })->delete;

      my $maps = schema(vars->{'tenant'})->resultset('AccessControlListMap')
                                         ->search({ acl_name => $acl })
        or return;

      schema(vars->{'tenant'})->resultset('AccessControlList')
        ->search({id => { -in => [ $maps->left_acls ] }})->delete;
      schema(vars->{'tenant'})->resultset('AccessControlList')
        ->search({id => { -in => [ $maps->right_acls ] }})->delete;

      $maps->delete;
    });

    return '';
};

ajax '/ajax/control/admin/aclmanager/update' => require_role setting('defanged_admin') => sub {
    my $acl = param('acl_name');
    my $old_acl = param('old-acl_name');
    send_error('Bad Request', 400) unless $acl and $old_acl;
    my $type = param('acl_type');
    send_error('Bad Request', 400) unless $type
      and $type =~ m/^(?:host|host_host|host_port)$/;

    schema('netdisco')->resultset('User')
      ->search({ portctl_role => $old_acl })
      ->update({ portctl_role => $acl });

    schema(vars->{'tenant'})->txn_do(sub {
      schema(vars->{'tenant'})->resultset('AccessControlListName')
        ->search({ acl_name => $old_acl })
        ->update({ acl_name => $acl, acl_type => $type });

      my $maps = schema(vars->{'tenant'})->resultset('AccessControlListMap')
                                         ->search({ acl_name => $old_acl });

      $maps->update({ acl_name => $acl });
      if ($type eq 'host') {
          schema(vars->{'tenant'})->resultset('AccessControlList')
            ->search({id => { -in => [ $maps->right_acls ] }})->delete;
      }
    });

    return '';
};

true;

