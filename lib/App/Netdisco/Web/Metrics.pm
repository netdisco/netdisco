package App::Netdisco::Web::Metrics;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

use App::Netdisco::Util::Permission 'acl_matches';
use Try::Tiny;

# Emit a gauge metric line with optional labels
sub _gauge {
  my ($name, $help, $value, %labels) = @_;
  my $label_str = '';
  if (%labels) {
    $label_str = '{'. join(',', map { qq($_="$labels{$_}") } sort keys %labels) .'}';
  }
  return sprintf("# HELP %s %s\n# TYPE %s gauge\n%s%s %s\n",
    $name, $help, $name, $name, $label_str, $value // 0);
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
  my %stat_metrics = (
    netdisco_devices_total        => 'Total number of discovered devices',
    netdisco_device_ips_total     => 'Total number of device IP addresses',
    netdisco_device_links_total   => 'Total number of layer2 links between devices',
    netdisco_device_ports_total   => 'Total number of device ports',
    netdisco_device_ports_up      => 'Total number of device ports with up/up status',
    netdisco_ip_table_total       => 'Total number of IP table entries',
    netdisco_ip_active_total      => 'Total number of active IP entries',
    netdisco_nodes_total          => 'Total number of node entries',
    netdisco_nodes_active_total   => 'Total number of active nodes',
    netdisco_phones_total         => 'Total number of discovered VoIP phones',
    netdisco_waps_total           => 'Total number of discovered wireless access points',
  );

  my %stat_columns = (
    netdisco_devices_total        => 'device_count',
    netdisco_device_ips_total     => 'device_ip_count',
    netdisco_device_links_total   => 'device_link_count',
    netdisco_device_ports_total   => 'device_port_count',
    netdisco_device_ports_up      => 'device_port_up_count',
    netdisco_ip_table_total       => 'ip_table_count',
    netdisco_ip_active_total      => 'ip_active_count',
    netdisco_nodes_total          => 'node_table_count',
    netdisco_nodes_active_total   => 'node_active_count',
    netdisco_phones_total         => 'phone_count',
    netdisco_waps_total           => 'wap_count',
  );

  foreach my $metric (sort keys %stat_metrics) {
    $output .= sprintf("# HELP %s %s\n# TYPE %s gauge\n",
      $metric, $stat_metrics{$metric}, $metric);

    foreach my $tenant (@tenants) {
      my $stats = try {
        schema($tenant)->resultset('Statistics')
          ->search(undef, { order_by => { -desc => 'day' }, rows => 1 })->first;
      };
      next unless $stats;
      my $col = $stat_columns{$metric};
      $output .= sprintf("%s{tenant=\"%s\"} %s\n",
        $metric, $tenant, $stats->$col // 0);
    }
    $output .= "\n";
  }

  # -- Job queue metrics (live, per tenant) ----------------------------------
  foreach my $tenant (@tenants) {
    my $rs = try { schema($tenant)->resultset('Admin') } or next;

    # Counts by status
    foreach my $st (qw/queued done error/) {
      my $count = try { $rs->search({ status => $st })->count } // 0;
      $output .= _gauge('netdisco_jobs_total',
        'Number of jobs in the queue by status',
        $count, tenant => $tenant, status => $st);
    }

    # Running (queued + assigned to backend)
    my $running = try {
      $rs->search({ status => 'queued', backend => { '!=' => undef } })->count;
    } // 0;
    $output .= _gauge('netdisco_jobs_running',
      'Number of jobs currently running',
      $running, tenant => $tenant);

    # Counts by action+status
    $output .= "# HELP netdisco_jobs_by_action Number of jobs grouped by action and status\n";
    $output .= "# TYPE netdisco_jobs_by_action gauge\n";
    my @by_action = try {
      $rs->search(undef, {
        select   => ['action', 'status', { count => '*', -as => 'cnt' }],
        as       => [qw/action status cnt/],
        group_by => [qw/action status/],
      })->hri->all;
    } catch { () };

    foreach my $row (@by_action) {
      $output .= sprintf(qq(netdisco_jobs_by_action{tenant="%s",action="%s",status="%s"} %s\n),
        $tenant, $row->{action}, $row->{status}, $row->{cnt});
    }
    $output .= "\n";

    # Average duration of completed jobs by action (in seconds)
    $output .= "# HELP netdisco_job_duration_seconds Average duration of completed jobs by action\n";
    $output .= "# TYPE netdisco_job_duration_seconds gauge\n";
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
    $output .= "\n";
  }

  return $output;
};

true;
