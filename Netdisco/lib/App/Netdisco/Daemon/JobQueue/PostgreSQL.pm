package App::Netdisco::Daemon::JobQueue::PostgreSQL;

use App::Netdisco::JobQueue::PostgreSQL ();

use Role::Tiny;
use namespace::clean;

sub jq_get      { shift and App::Netdisco::JobQueue::PostgreSQL::jq_get(@_) }
sub jq_getlocal { shift and App::Netdisco::JobQueue::PostgreSQL::jq_getlocal(@_) }
sub jq_queued   { shift and App::Netdisco::JobQueue::PostgreSQL::jq_queued(@_) }
sub jq_lock     { shift and App::Netdisco::JobQueue::PostgreSQL::jq_lock(@_) }
sub jq_defer    { shift and App::Netdisco::JobQueue::PostgreSQL::jq_defer(@_) }
sub jq_complete { shift and App::Netdisco::JobQueue::PostgreSQL::jq_complete(@_) }
sub jq_insert   { shift and App::Netdisco::JobQueue::PostgreSQL::jq_insert(@_) }

1;
