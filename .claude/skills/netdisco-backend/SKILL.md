---
name: netdisco-backend
description: Use when changing or reviewing Netdisco's backend, meaning worker plugins under lib/App/Netdisco/Worker, the job queue and who may queue a job, the SNMP and SSH transports, how a worker uses what SNMP::Info returns, or a Python worklet, including their xt tests. Writing an SSH collector platform has its own skill, netdisco-ssh-collector.
---

# Working on Netdisco's backend workers

A job runs through phases of worker plugins. Workers read a device through
SNMP::Info or an SSH collector and leave data for a later phase to store.
The mistakes to avoid are storing a short read as if it were whole,
returning a status that tells the operator the wrong thing, and letting a
user queue more than their role allows. Read `AGENTS.md` first. Writing
rows (upserts, lock order, timestamps) is in
`.claude/skills/netdisco-database/SKILL.md`; writing an SSH collector
platform is in `.claude/skills/netdisco-ssh-collector/SKILL.md`.

## Worker plugins

- **`register_worker`** (`Worker/Plugin.pm`) takes the action and
  namespace from the package: `Plugin::Arpnip::Nodes` is `arpnip`,
  namespace `nodes`, which `netdisco-do arpnip::nodes` runs alone.
- **A worker with no `phase` runs in `user`.** `only => ACL` runs it just
  for devices that match every rule (`acl_matches_only`), and `no => ACL`
  skips devices that match any; a skipped worker logs
  `skip: acls restricted`. Both take the device ACL syntax used across the
  configuration (`vendor:juniper`, `group:core`, a prefix).
- **Phases run in order:** `check`, `early`, `main`, `user`, `store`,
  `late` (`Worker/Runner.pm`). Every `main` worker runs: one returning
  `done` does not stop the next.
- **Drivers run cheapest first, so the most trusted one wins.** A worker
  with `driver => 'snmp'` takes its priority from `driver_priority`
  (`snmp` 100, `cli` 200, `api` 300, up to `direct`). Within a phase and
  namespace, `Worker/Loader.pm` runs priorities from low to high. Workers
  share the job's `vars`, so the last to write, the highest priority
  driver, overwrites what the others left: an SNMP arpnip runs first and a
  CLI arpnip then adds to or replaces its entries.
- **A driver worker needs credentials for its driver.** It runs only when
  a `device_auth` stanza for the device names that driver or none;
  otherwise it logs `skip: driver or action not applicable`. An offline
  job skips networked `main` workers.
- **The check phase gates the job.** If any check worker returns a
  status, one must be `done` or no later phase runs (`check_passed` in
  `Backend/Job.pm`). Refuse there when the device is not stored, not
  eligible or not permitted (`Worker/Plugin/Arpnip.pm`,
  `PortControl.pm`). A check's `done` is never the job's result.
- **`vars` is per-job state.** A backend poller exits after each job
  (`Backend/Role/Poller.pm`), but `netdisco-do` runs all its jobs in one
  process, so reset your keys in `early`, as `Arpnip/Nodes.pm` does.
- A worker that dies is recorded as `error` and the next still runs.
  `$job->cancel($msg)` returns an error and skips the rest.
- **Site plugins:** `X::Foo` in `extra_worker_plugins` loads
  `App::NetdiscoX::Worker::Plugin::Foo` from `~/nd-site-local/lib`
  (`Worker/Actions.pm`). They read core workers' `vars` and call platform
  methods, so say in the PR when you change either.

## Actions

One or two lines each; read the model file before changing the action.

- **discover** (`Discover.pm`, `Discover/`): `Properties.pm` runs in
  `early` and creates the device row, so `netdisco-do discover::NAME`
  still runs it for a device not yet stored (`Worker/Plugin.pm`). Ports
  honour `ignore_interfaces`, `ignore_interface_types` and
  `ignore_notpresent_types`; `discover_no` and `discover_only` limit which
  devices are discovered. `Neighbors.pm` queues new neighbors.
- **macsuck** (`Macsuck/Nodes.pm`): forwarding tables, per VLAN where the
  device needs it (see SNMP contexts). `macsuck_no_vlan`,
  `macsuck_no_devicevlan` and `macsuck_no_deviceports` skip VLANs and
  ports; MACs on uplinks and neighbor ports are not nodes unless
  `macsuck_bleed`; `sanity_macs` drops invalid ones.
- **arpnip** (`Arpnip/Nodes.pm`, `Arpnip/Subnets.pm`): ARP and IPv6
  neighbor entries and subnets, by SNMP and CLI; the model for a worker
  with every phase and driver.
- **Hooks:** each action's `Hooks.pm` (`late` phase) queues the hooks in
  `hooks` with `queue_hook` (`Util/Worker.pm`); `Hook/Exec.pm` and
  `Hook/HTTP.pm` run them. They read `$job->best_status` and
  `vars->{'hook_data'}`.
- **User actions** (`PortControl`, `Power`, `PortName`, `Vlan`, `Contact`,
  `Location`) write to the device: see Job permissions and SNMP writes.
- **Walks and housekeeping:** `DiscoverAll`, `Macwalk`, `Arpwalk` and
  `Nbtwalk` queue one job per device; `Expire`, `ExpireNodes`, `Delete`
  and `Renumber` change stored data without polling. The `schedule`
  setting queues them; `job_prio` orders the queue.
- **Skipped devices:** a device whose jobs keep returning `defer` is held
  back after `workers.max_deferrals` (`JobQueue/PostgreSQL.pm`).
  `PrimeSkiplist` records, per device, the actions configuration denies it
  (`get_denied_actions`, from settings such as `devices_no` and
  `discover_no`).

## Job permissions

Jobs arrive from the web UI, the API, inline actions, the scheduler and
`netdisco-do`, and a web route's check does not protect the others. These
rules closed real findings; keep them when adding an action.

- **Some actions are `netdisco-do` only.** `Util/JobAction.pm` lists the
  actions the web and API refuse to queue (`hook`, `scheduler`, `psql`,
  `getapikey`, `dumpconfig`, `dumpinfocache`, `show`), checked in
  `Web/API/Queue.pm` and `Web/AdminTask.pm` (`xt/88-job-action-refusal.t`).
  A new action that exposes configuration, credentials or the database
  goes in that list.
- **A job field must never reach configuration without the admin check.**
  `port` and `subaction` can carry configuration overrides, applied in the
  poller by `apply_config_overrides` (`Backend/Job.pm`). Routes that queue
  for non-admins refuse them through `carries_config_overrides`
  (`Web/PortControl.pm`, `Web/API/Queue.pm`;
  `xt/102-config-overrides-need-admin.t`,
  `xt/101-job-overrides-in-poller.t`). Configuration decides which
  devices the backend contacts, with which credentials, and what it runs,
  so changing it is an administrator's right, whichever route the job
  came through.
- **Non-admins queue only `nonadmin_actions`** (by default `discover`,
  `arpnip`, `macsuck` and `nbtstat`), when `enable_nonadmin_actions` is on
  (`Web/AdminTask.pm`).
- **A write checks permission in its own check phase**, against the job's
  `username`, with `port_acl_check`, `port_acl_service`, `port_acl_pvid`
  or `device_acl_by_role_check` (`Util/Port.pm`), as `PortControl`,
  `Power`, `PortName` and `Vlan` do. Do not rely on the route that queued
  it.

## Status values

From `Worker/Status.pm`, `Backend/Job.pm` and `JobQueue/PostgreSQL.pm`:

- **`done`:** the action did what it is for; its message becomes the job
  log. Store workers set `last_arpnip` or `last_macsuck` only when
  `$job->best_status` is `done` (`Arpnip/Nodes.pm`, `Macsuck/Nodes.pm`).
- **`info`:** finished or skipped, but not the action's result: nothing to
  do, or rows kept after a short walk.
- **`defer`:** only when the worker failed to connect to the device or
  is not permitted to (no credentials). The job is requeued and the
  device's deferral count rises, holding back every action on it; a
  completed device job resets the count.
- **`error`:** something that should not happen. It outranks every other
  status, so one error becomes the job's result.
- Write messages for the operator reading the job queue: name the device,
  what was read and what was kept. Log detail at `debug`, and use
  `warning` only for something an operator must act on.

## SNMP transport

- **`reader_for($device)`** (`Transport/SNMP.pm`) caches one SNMP::Info
  object per device address for the process, shared by every worker in
  the job. A failed connect is cached too. On undef, return `defer`.
- **`IncompleteWalk => 'partial'` is pinned:** a table method returns the
  rows read before a walk ended, and the worker decides what that means.
- **Writes:** `writer_for` uses the read-write communities and refuses
  pseudo devices. Its connection test writes `sysLocation` back, so
  opening a writer is itself an SNMP SET. Only user actions call it,
  after their check-phase permission check. Never call it from discover,
  macsuck, arpnip or any other read.

## SNMP contexts

Some devices serve a table only in a separate SNMP context: one per VLAN,
per MST instance or per VRF. SNMP::Info (3.983000 on) says which features
need one with `context_kinds($feature)` (`fdb`, `stp`, `vrf`) and how to
address each with `snmp_context($kind, $id)`: the SNMPv2c community form
(`public@10` on Cisco, `default::10@public` on Junos) and the SNMPv3
context name, or undef where that SNMP version cannot reach it, as on
NX-OS over SNMPv2c.

- **Per VLAN (forwarding tables):** `snmp_comm_reindex($snmp, $device,
  $vlan)` (`Util/SNMP.pm`) builds `community@vlan`, or on SNMPv3
  `vlan-N` or the credentials' `context_prefix`. Macsuck and discover use
  it only when `cisco_comm_indexing` is true, which is also when
  `context_kinds('fdb')` answers `vlan`.
- **Per VRF:** `snmp_vrf_context` takes the context from the VRF record
  SNMP::Info returns (see VRFs).
- **Spanning tree:** Netdisco does not read it yet. SNMP::Info serves it
  per VLAN on Cisco PVST and Juniper VSTP, and per VLAN or MST instance on
  Nexus.
- **New code asks SNMP::Info** with `context_kinds` and `snmp_context`
  instead of building `community@N` itself.
- **Leave the shared session as you found it.** `update()` clears
  SNMP::Info's cache, so read what you need first, and restore the default
  context with a guard that runs however the worker exits, as
  `Macsuck/Nodes.pm` does with `snmp_comm_reindex($snmp, $device, 0)`.

## What SNMP::Info gives a worker

`Build.PL` names the SNMP::Info release Netdisco requires. Find the
release that added anything you call in SNMP::Info's `Changes`, and raise
the requirement in the same PR when needed.

- **A short walk must not clear stored rows** (walk records: SNMP::Info
  3.980000). Take `walk_mark($snmp)`, read, then call
  `incomplete_walks_for($device, $snmp, $mark, @methods)` naming every
  method whose rows you write (and `interfaces` when rows key on ports).
  If it returns anything, write what was read, delete nothing, log
  `incomplete_walk_message(...)` at `warning`, and return the Status
  `incomplete_walk_level(...)` names: `error` when a walk was `absent`
  (broken MIBs on the poller), else `info`. Model: `store_neighbors` in
  `Discover/Neighbors.pm`.
- **`$snmp->error`** holds the latest error and clears when read.
  SNMP::Info prints it only with `Debug` (`INFO_TRACE`), so read it once
  and put it in your Status, as `PortControl.pm` does. To report only one
  read's error, read and discard it before that read.
- **LLDP neighbors with only a MAC chassis ID:** from SNMP::Info 3.985001
  (netdisco/snmp-info#680) `lldp_ip`, and so `c_ip`, returns `0.0.0.0`
  for them in every class that uses `SNMP::Info::LLDP` (3.985000 did so
  for Dell only). A class that reads LLDP from its own MIB may still leave
  them out, as F5OS does. `store_neighbors` treats `0.0.0.0` as no
  address and looks the neighbor up by `c_id` among known devices (name,
  then MAC), skipping it when none matches. Never store or contact
  `0.0.0.0`.
- **A fix to how a device is read belongs in SNMP::Info:** fix the device
  class there (see its `AGENTS.md` and `device-class-authoring` skill),
  then require that release. Do not add vendor branches to a worker to
  correct a class.

## VRFs

Collection is off unless `store_vrfs` is on.

- **`vrf_collection_enabled($device)`** (`Util/VRF.pm`) is false when
  `store_vrfs` is off, the device matches `skip_vrf_devices`, or it is a
  pseudo device. For a new device it is reliable only after `reader_for`.
- **`vrf_skip_test($device)`** returns a test for the VRF names
  `vrf_no_devicevrfs` skips on the device. Build it once, before a loop:
  building it matches the device against every key, and a hostname key
  costs a DNS lookup.
- **`vrf_instances_for($device, $snmp)`** is undef when collection is off
  or the class has no VRF support; then take the existing path unchanged.
  **`each_vrf_instance`** reads each VRF in place or in its own context
  and reports each as complete or not. Store only complete VRFs; a VRF
  read short keeps its rows. Models: `store_vrf_subnets`
  (`Arpnip/Subnets.pm`), `gather_arps_per_vrf` (`Arpnip/Nodes.pm`).
- **After changing a device's `device_vrf` rows,** call
  `recompute_l3_domains` only when `l3_domain_recompute_needed` says so,
  after the rows are written (`Util/L3Domain.pm`; models:
  `_recompute_l3_domains_after` in `Discover/Properties.pm`,
  `record_cli_vrfs` in `Util/Node.pm`). The recompute is network wide and
  takes advisory lock class 1729.
- **To find the device an address belongs to,** use `get_device`
  (`Util/Device.pm`) or `DeviceIp->resolve_alias`. Both follow one rule
  (`device_ip_resolved`): with VRFs, an address can belong to several
  devices, and a search on `device_ip.alias` alone can match several.

## SSH collectors, from the worker's side

- **`session_for($device)`** (`Transport/SSH.pm`) needs exactly one
  `device_auth` stanza left for the device and driver, naming a
  `platform` (a stanza without one is for a Python worklet). A failure is
  not cached. On undef, return `defer`.
- **Platform methods** are called as `$platform->method($host, $ssh,
  $auth)`; the session returns nothing for one the platform lacks. Their
  return shapes, and how a platform reports what it read whole, are in
  the SSH collector skill.
- **Never retire on a partial read.** `retire_unvouched_arps`
  (`Util/Node.pm`) retires only VRFs read whole, skipped VRFs and, when
  the list was whole, VRFs no longer listed; a job with no VRF reads
  retires nothing.

## Python worklets

- Worklets live in `share/python/netdisco/netdisco/worklet/<action>/`.
  An entry in `python_worker_plugins` names one as
  `action.namespace.phase[.driver[.platform]]`; a mapping entry's value
  adds worker options such as `only` and `no`, or lists drivers
  (`PythonShim.pm`). `PythonShim` runs them through `Transport/Python.pm`.
- The job reaches Python as `JobManager` (`netdisco/util/job.py`), which
  rejects keys it does not know: state the Perl side keeps per job stays
  off the job object (`Backend/Job.pm`).
- Tests and ruff settings are in `share/python/netdisco/` (`tests/`,
  `ruff.toml`).

## Tests

- **Fake the transport, run the real worker.** Worker tests build a
  `MyWorker` with the `App::Netdisco::Worker::Runner` role, replace
  `reader_for` with `local *App::Netdisco::Transport::SNMP::reader_for`,
  and give it a fake SNMP::Info that records `walk_failures`. Models:
  `xt/175-discover-neighbor-columns.t`, `xt/165-incomplete-walks-for.t`.
- Test the short read as well as the whole one: a walk that fails
  partway, a command that times out, an empty table.
- A new action or route that queues jobs: test the refusal for a user who
  may not queue it, beside `xt/88` and `xt/102`.
- In the PR, describe the devices you tested (vendor, model, OS
  version), the actions you ran, and what the job logged and returned
  (`netdisco-do ACTION -d DEVICE -D`).

## Before you open the PR

- [ ] The branch is current `master`. Never copy a file from an installed
      release or an older checkout: that silently reverts every change
      made since, short-walk guards included.
- [ ] `defer` only for connect or credential failures; Status messages
      name the device; new log lines are `debug` unless an operator must
      act.
- [ ] A short read keeps stored rows, and a test proves it.
- [ ] A new action is refused to the users who should not queue it, and a
      write checks permission in its own check phase.
- [ ] A fix to how a device is read went to SNMP::Info, or the PR says
      why not; `Build.PL` requires the release with every SNMP::Info
      method you call.
