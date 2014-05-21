package App::Netdisco::Daemon::JobQueue;

use Role::Tiny;
use namespace::clean;

use Module::Load ();
Module::Load::load_remote 'JobQueue' => 'App::Netdisco::JobQueue' => ':all';

# central queue
sub jq_getsome  { shift and JobQueue::jq_getsome(@_) }
sub jq_locked   { shift and JobQueue::jq_locked(@_) }
sub jq_queued   { shift and JobQueue::jq_queued(@_) }
sub jq_take     { goto \&JobQueue::jq_take }
sub jq_lock     { shift and JobQueue::jq_lock(@_) }
sub jq_defer    { shift and JobQueue::jq_defer(@_) }
sub jq_complete { shift and JobQueue::jq_complete(@_) }
sub jq_insert   { shift and JobQueue::jq_insert(@_) }

1;
