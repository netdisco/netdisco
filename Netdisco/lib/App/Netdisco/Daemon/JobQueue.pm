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

=head1 NAME

App::Netdisco::Daemon::JobQueue

=head1 DESCRIPTION

Interface for Netdisco job queue.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 jq_get( $num? )

Returns a list of randomly selected queued jobs. Default is to return one job,
unless C<$num> is provided. Jobs are returned as objects which implement the
Netdisco job instance interface (see below).

=head2 jq_getlocal()

Returns the list of jobs currently booked out to this processing node (denoted
by the local hostname). Jobs are returned as objects which implement the
Netdisco job instance interface (see below).

=head2 jq_queued( $job_type )

Returns a list of IP addresses of devices which currently have a job of the
given C<$job_type> queued (e.g. C<discover>, C<arpnip>, etc).

=head2 jq_lock( $job )

Marks a job in the queue as booked out to this processing node (denoted by the
local hostname). The C<$job> parameter must be an object which implements the
Netdisco job instance interface (see below).

Returns true if successful else returns false.

=head2 jq_defer( $job )

Marks a job in the queue as available for taking. This is usually done after a
job is booked but the processing node changes its mind and decides to return
the job to the queue. The C<$job> parameter must be an object which implements
the Netdisco job instance interface (see below).

Returns true if successful else returns false.

=head2 jq_complete( $job )

Marks a job as complete. The C<$job> parameter must be an object which
implements the Netdisco job instance interface (see below). The queue item's
status, log and finished fields will be updated from the passed C<$job>.

Returns true if successful else returns false.

=head2 jq_insert( \%job | [ %job, \%job ...] )

Adds the passed jobs to the queue.

=head1 Job Instance Interface

=head2 id (auto)

=head2 type (required)

=head2 wid (required, default 0)

=head2 entered

=head2 started

=head2 finished

=head2 device

=head2 port

=head2 action

=head2 subaction or extra

=head2 status

=head2 username

=head2 userip

=head2 log

=head2 debug

=cut

true;
