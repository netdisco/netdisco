package App::Netdisco::JobQueue;

use Dancer qw/:moose :syntax :script/;

use Module::Load ();
Module::Load::load
  'App::Netdisco::JobQueue::' . setting('workers')->{queue} => ':all';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  jq_getsome
  jq_getsomep
  jq_locked
  jq_queued
  jq_log
  jq_userlog
  jq_lock
  jq_defer
  jq_complete
  jq_insert
  jq_delete
/;
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

=head1 NAME

App::Netdisco::JobQueue

=head1 DESCRIPTION

Interface for Netdisco job queue.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 jq_getsome( $num? )

Returns a list of randomly selected queued jobs. Default is to return one job,
unless C<$num> is provided. Jobs are returned as objects which implement the
Netdisco job instance interface (see below).

=head2 jq_getsomep( $num? )

Same as C<jq_getsome> but for high priority jobs.

=head2 jq_locked()

Returns the list of jobs currently booked out to this processing node (denoted
by the local hostname). Jobs are returned as objects which implement the
Netdisco job instance interface (see below).

=head2 jq_queued( $job_type )

Returns a list of IP addresses of devices which currently have a job of the
given C<$job_type> queued (e.g. C<discover>, C<arpnip>, etc).

=head2 jq_log()

Returns a list of the most recent 50 jobs in the queue. Jobs are returned as
objects which implement the Netdisco job instance interface (see below).

=head2 jq_userlog( $user )

Returns a list of jobs which have been entered into the queue by the passed
C<$user>. Jobs are returned as objects which implement the Netdisco job
instance interface (see below).

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

=head2 jq_insert( \%job | [ \%job, \%job ...] )

Adds the passed jobs to the queue.

=head2 jq_delete( $id? )

If passed the ID of a job, deletes it from the queue. Otherwise deletes ALL
jobs from the queue.

=head1 Job Instance Interface

=head2 id (auto)

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
