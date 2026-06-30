package App::Netdisco::Web::Plugin::AdminTask::Divider;

use Dancer ':syntax';
use App::Netdisco::Web::Plugin;

register_admin_task({ tag => 'divider', label => 'Divider' });

1;
