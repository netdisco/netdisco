package App::Netdisco::Daemon::JobQueue;

use Dancer qw/:moose :syntax :script/;

use Role::Tiny;
use namespace::clean;

use Module::Load ();
Module::Load::load_remote 'JobQueue' =>
  'App::Netdisco::JobQueue::' . setting('job_queue') => ':all';

sub jq_get      { shift and JobQueue::jq_get(@_) }
sub jq_getlocal { shift and JobQueue::jq_getlocal(@_) }
sub jq_queued   { shift and JobQueue::jq_queued(@_) }
sub jq_lock     { shift and JobQueue::jq_lock(@_) }
sub jq_defer    { shift and JobQueue::jq_defer(@_) }
sub jq_complete { shift and JobQueue::jq_complete(@_) }
sub jq_insert   { shift and JobQueue::jq_insert(@_) }

true;
