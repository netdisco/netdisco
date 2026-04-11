package App::Netdisco::Web::Metrics;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

use App::Netdisco::Util::Permission 'acl_matches';
use Try::Tiny;

sub _header {
  my ($name, $help) = @_;
  return sprintf("# HELP %s %s\n# TYPE %s gauge\n", $name, $help, $name);
}

sub _sample {
  my ($name, $value, %labels) = @_;
  my $label_str = '';
  if (%labels) {
    $label_str = '{'. join(',', map { qq($_="$labels{$_}") } sort keys %labels) .'}';
  }
  return sprintf("%s%s %s\n", $name, $label_str, $value // 0);
}

get '/metrics' => sub {
  # Optional IP range restriction
  my $allow = setting('metrics_allow');
  if ($allow and ref $allow eq ref []) {
    my $remote = request->remote_address;
    unless (acl_matches($remote, $allow)) {
      status 403;
      return 'Forbidden';
    }
  }

  # Optional bearer token auth
  my $token = setting('metrics_token');
  if ($token) {
    my $auth = request->header('Authorization') // '';
    unless ($auth eq "Bearer $token") {
      status 401;
      header 'WWW-Authenticate' => 'Bearer realm="netdisco metrics"';
      return 'Unauthorized';
    }
  }

  content_type 'text/plain; version=0.0.4; charset=utf-8';

  my @tenants = ('netdisco');
  if (my $tdbs = setting('tenant_databases')) {
    push @tenants, map { $_->{'tag'} } @$tdbs;
  }

  my $output = '';

  # -- Statistics metrics (one row per tenant) -------------------------------
  my @stat_metrics = (
    [ netdisco_devices_total      => 'device_count',        'Total number of discovered devices' ],
    [ netdisco_device_ips         => 'device_ip_count',     'Total number of device IP addresses' ],
    [ netdisco_device_links       => 'device_link_count',   'Total number of layer2 links between devices' ],
    [ netdisco_device_ports       => 'device_port_count',   'Total number of device ports' ],
    [ netdisco_device_ports_up    => 'device_port_up_count','Total number of device ports with up/up status' ],
    [ netdisco_ip_table           => 'ip_table_count',      'Total number of IP table entries' ],
    [ netdisco_ip_active          => 'ip_active_count',     'Total number of active IP entries' ],
    [ netdisco_nodes              => 'node_table_count',    'Total number of node entries' ],
    [ netdisco_nodes_active       => 'node_active_count',   'Total number of active nodes' ],
    [ netdisco_phones             => 'phone_count',         'Total number of discovered VoIP phones' ],
    [ netdisco_waps               => 'wap_count',           'Total number of discovered wireless access points' ],
  );

  foreach my $m (@stat_metrics) {
    my ($metric, $col, $help) = @$m;
    $output .= _header($metric, $help);
    foreach my $tenant (@tenants) {
      my $stats = try {
        schema($tenant)->resultset('Statistics')
          ->search(undef, { order_by => { -desc => 'day' }, rows => 1 })->first;
      };
      next unless $stats;
      $output .= _sample($metric, $stats->$col // 0, tenant => $tenant);
    }
    $output .= "\n";
  }

  # -- Job queue metrics (live, per tenant) ----------------------------------

  # Counts by status
  $output .= _header('netdisco_jobs', 'Number of jobs in the queue by status');
  foreach my $tenant (@tenants) {
    my $rs = try { schema($tenant)->resultset('Admin') } or next;
    foreach my $st (qw/queued done error/) {
      my $count = try { $rs->search({ status => $st })->count } catch { 0 };
      $output .= _sample('netdisco_jobs', $count, tenant => $tenant, status => $st);
    }
  }
  $output .= "\n";

  # Running jobs
  $output .= _header('netdisco_jobs_running', 'Number of jobs currently running');
  foreach my $tenant (@tenants) {
    my $rs = try { schema($tenant)->resultset('Admin') } or next;
    my $running = try {
      $rs->search({ status => 'queued', backend => { '!=' => undef } })->count;
    } catch { 0 };
    $output .= _sample('netdisco_jobs_running', $running, tenant => $tenant);
  }
  $output .= "\n";

  # Counts by action+status
  $output .= _header('netdisco_jobs_by_action', 'Number of jobs grouped by action and status');
  foreach my $tenant (@tenants) {
    my $rs = try { schema($tenant)->resultset('Admin') } or next;
    my @by_action = try {
      $rs->search(undef, {
        select   => ['action', 'status', { count => '*', -as => 'cnt' }],
        as       => [qw/action status cnt/],
        group_by => [qw/action status/],
      })->hri->all;
    } catch { () };
    foreach my $row (@by_action) {
      $output .= _sample('netdisco_jobs_by_action', $row->{cnt},
        tenant => $tenant, action => $row->{action}, status => $row->{status});
    }
  }
  $output .= "\n";

  # Average duration of completed jobs by action
  $output .= _header('netdisco_job_duration_seconds', 'Average duration of completed jobs by action in seconds');
  foreach my $tenant (@tenants) {
    my $rs = try { schema($tenant)->resultset('Admin') } or next;
    my @durations = try {
      $rs->search(
        { status => 'done', started => { '!=' => undef }, finished => { '!=' => undef } },
        {
          select   => ['action',
            { avg => \"extract(epoch FROM (finished - started))", -as => 'avg_duration' }],
          as       => [qw/action avg_duration/],
          group_by => ['action'],
        }
      )->hri->all;
    } catch { () };
    foreach my $row (@durations) {
      next unless defined $row->{avg_duration};
      $output .= sprintf(qq(netdisco_job_duration_seconds{tenant="%s",action="%s"} %.3f\n),
        $tenant, $row->{action}, $row->{avg_duration});
    }
  }
  $output .= "\n";

  return $output;
};

true;
