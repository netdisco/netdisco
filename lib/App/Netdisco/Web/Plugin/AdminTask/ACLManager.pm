package App::Netdisco::Web::Plugin::AdminTask::ACLManager;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Ajax;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::ManagedConfig
  qw/acl_txn_do yaml_setting is_reserved_group_name/;

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
    # a host ACL becomes host_groups->{<name>}, so it must not take a name
    # Netdisco relies on, such as __ANY__
    send_error('Bad Request', 400)
      if $type eq 'host' and is_reserved_group_name($acl);
    send_error('Bad Request', 400)
      if schema(vars->{'tenant'})->resultset('AccessControlListName')
                                 ->search({acl_name => $acl})->count();

    acl_txn_do(sub {
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

    unless (exists +(yaml_setting('portctl_by_role') || {})->{$acl}) {
      schema('netdisco')->txn_do(sub {
        my $users = schema('netdisco')->resultset('User');

        # "contained by" rather than equality: a user left holding only this
        # name more than once, or holding an empty list, must have port
        # control turned off. array_remove below would otherwise leave them
        # with {}, which the role checks read as "Enabled (any port)".
        $users->search(\[ 'portctl_roles <@ ARRAY[?]::text[]', $acl ])
          ->update({ portctl_roles => undef, port_control => \'false' });

        $users->search(\[ '? = ANY(portctl_roles)', $acl ])
          ->update({ portctl_roles => \[ 'array_remove(portctl_roles, ?)', $acl ] });
      });
    }

    schema('netdisco')->resultset('User')
      ->search({token_acl => $acl})
      ->update({token_acl => undef});

    acl_txn_do(sub {
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
    # as for add: also reached by turning a role into a host ACL
    send_error('Bad Request', 400)
      if $type eq 'host' and is_reserved_group_name($acl);

    acl_txn_do(sub {
      schema(vars->{'tenant'})->resultset('AccessControlListName')
        ->search({ acl_name => $old_acl })
        ->update({ acl_name => $acl, acl_type => $type });

      my $maps = schema(vars->{'tenant'})->resultset('AccessControlListMap')
                                         ->search({ acl_name => $old_acl });

      $maps->update({ acl_name => $acl });
      if ($type eq 'host') {
          schema(vars->{'tenant'})->resultset('AccessControlList')
            ->search({id => { -in => [ $maps->right_acls ] }})
            ->update({ rules => [] });
      }
    });

    # Users are renamed only once the ACL rename has committed. Renaming onto
    # a name that already exists fails on the acl_name primary key, and when
    # users were renamed first they kept the new name anyway: a user moved
    # onto the other ACL's rights, or one holding both was left with the name
    # twice. Users live in the default database and a tenant's ACLs in its
    # own, so one transaction cannot cover both; the ordering does instead,
    # as acl_txn_do throws before this runs.
    schema('netdisco')->resultset('User')
      ->search(\[ '? = ANY(portctl_roles)', $old_acl ])
      ->update({ portctl_roles => \[ 'array_replace(portctl_roles, ?, ?)', $old_acl, $acl ] });

    return '';
};

true;

