package App::Netdisco::Daemon::JobQueue;

use Dancer qw/:moose :syntax :script/;

use Role::Tiny;
use namespace::clean;

with 'App::Netdisco::Daemon::JobQueue::'. setting('job_queue');

requires qw/
  jq_get
  jq_getlocal
  jq_queued
  jq_lock
  jq_defer
  jq_complete
  jq_insert
/;

true;
