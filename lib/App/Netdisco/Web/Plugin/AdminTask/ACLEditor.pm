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
      ->search({acl_name => $acl_name}, { prefetch => ['left_acl_with_dns',
          ($acl->acl_type eq 'host_host' ? 'right_acl_with_dns' : 'right_acl') ],
          order_by => 'me.id' })
      or send_error('Bad Request', 400);

    template 'ajax/admintask/acleditor.tt', {
      acl_name => $acl->acl_name,
      results => $maps,
    }, { layout => undef };
};

post '/ajax/control/admin/acleditor/add' => require_role setting('defanged_admin') => sub {
    my $acl = param("acl_name");
    my $left_rule = param("left_rule");
    my $right_rule = param("right_rule");
    send_error('Bad Request', 400) unless $left_rule and $acl;

    schema(vars->{'tenant'})->txn_do(sub {
      my $row = schema(vars->{'tenant'})->resultset('AccessControlListMap')
        ->create({
          acl_name => $acl,
          left_acl => {}, right_acl => {},
        });

      $row->left_acl->update({
          rules => [ $left_rule ],
      });
      $row->right_acl->update({
          rules => [ $right_rule ],
      }) if $right_rule;
    });

    return '';
};

post '/ajax/control/admin/acleditor/delete' => require_role setting('defanged_admin') => sub {
    my $id = param("id");
    my $acl = param("acl_name");
    send_error('Bad Request', 400) unless $id and $acl;
    
    schema(vars->{'tenant'})->txn_do(sub {
      my $map = schema(vars->{'tenant'})->resultset('AccessControlListMap')
        ->find($id) or send_error('Bad Request', 400);

      schema(vars->{'tenant'})->resultset('AccessControlList')
        ->find($map->left_acl_id)->delete;
      schema(vars->{'tenant'})->resultset('AccessControlList')
        ->find($map->right_acl_id)->delete
      if schema(vars->{'tenant'})->resultset('AccessControlList')
        ->find($map->right_acl_id);

      $map->delete;

      if (schema(vars->{'tenant'})->resultset('AccessControlListMap')
            ->search({ acl_name => $acl })->count() == 0) {
          # ACLs cannot be empty - restore as a bare ACL
          my $new = schema(vars->{'tenant'})->resultset('AccessControlListMap')
            ->create({
              acl_name => $acl,
              left_acl => {}, right_acl => {},
            });
          $new->left_acl->update({ rules => ['group:__ANY__'] });
          $new->right_acl->update({ rules => ['group:__ANY__'] })
            if param("acl_type") and param("acl_type") eq 'host_host';
      }
    });

    return '';
};

post '/ajax/control/admin/acleditor/update' => require_role setting('defanged_admin') => sub {
    my $id = param("id");
    my $acl = param("acl_name");
    send_error('Bad Request', 400) unless $id and $acl;

    my @left_rules = map  {decode_base64($_)}
                     map  { s/^\d+\.//; $_ }
                     sort { 
                        my ($aa, $bb) = map { (split /\./)[0] } $a, $b;
                        $aa <=> $bb;
                     }
                         @{ ref param('left_rule') ? param('left_rule')
                                                  : defined param('left_rule') ? [param('left_rule')]
                                                                               : [] };
    @left_rules = ('group:__ANY__') if 0 == scalar @left_rules;

    my @right_rules   = map  {decode_base64($_)}
                        map  { s/^\d+\.//; $_ }
                        sort { 
                            my ($aa, $bb) = map { (split /\./)[0] } $a, $b;
                            $aa <=> $bb;
                        }
                            @{ ref param('right_rule') ? param('right_rule')
                                                      : defined param('right_rule') ? [param('right_rule')]
                                                                                    : [] };

    schema(vars->{'tenant'})->txn_do(sub {
      my $row = schema(vars->{'tenant'})->resultset('AccessControlListMap')
        ->find($id) or send_error('Bad Request', 400);

      schema(vars->{'tenant'})->resultset('AccessControlList')
        ->find($row->left_acl_id)->update({rules => \@left_rules });
      schema(vars->{'tenant'})->resultset('AccessControlList')
        ->find($row->right_acl_id)->update({rules => \@right_rules });
    });

    return '';
};

true;

