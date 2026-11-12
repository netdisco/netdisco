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

This skill states rules and names the file that owns the details. Where
they seem to disagree, the code is right; say so in the PR.

## Worker plugins

- **Registration, phases and options** are in `Worker/Plugin.pm`
  (`register_worker`), `Worker/Runner.pm` (phase order) and
  `Worker/Loader.pm` (run order). Driver priorities are `driver_priority`
  in `share/config.yml`. The package name gives the action
  and namespace: `Plugin::Arpnip::Nodes` is `netdisco-do arpnip::nodes`.
  `only` and `no` take device ACLs (`Util/Permission.pm`): a list matches
  when any rule does, or every rule when it holds `op:and`, and an empty
  `only` matches every device.
- **Every `main` worker runs.** One returning `done` does not stop the
  next.
- **Name a phase.** The default is `user`, which `best_status`
  (`Backend/Job.pm`) ignores, so a `done` there never lets the store
  workers or hooks run.
- **A worker with a driver priority below `direct` is networked:** it is
  skipped when no `device_auth` stanza is left for it, and, in `main`,
  when the job runs offline (`Worker/Plugin.pm`).
- **Workers share the job's `vars`,** and higher priority drivers run
  later, but each action merges in its own way. Read the action's merge
  before relying on which driver wins, and read its `early` and `store`
  workers before relying on the shape of a key: `subnets` is keyed by VRF,
  and `arps` is a hash until the store phase makes it a list.
- **The check phase gates the job** (`check_passed` in `Backend/Job.pm`).
  Refuse there when the device is not stored, not eligible or not
  permitted, as `Arpnip.pm` and `PortControl.pm` do. A check's `done` is
  never the job's result.
- **`vars` is per-job state, but not per process.** `netdisco-do` runs all
  its jobs in one process, so reset your keys in `early`, as
  `Arpnip/Nodes.pm` does.
- **Site plugins** (`App::NetdiscoX::Worker::Plugin::*`, mapped in
  `Worker/Actions.pm`) read core workers' `vars` and call platform
  methods, so say in the PR when you change either.

## Actions

Read the action's own files before changing it; they state its settings
and filters. The user actions, which write to the device, are
`PortControl`, `Power`, `PortName`, `Vlan`, `Contact` and `Location`.
`Arpnip/` is the model for a worker with every phase and driver,
`Discover/Neighbors.pm` for handling a short walk, and an action's
`Hooks.pm` for queuing hooks.

## Job permissions

Jobs arrive from the web UI, the API, inline actions, the scheduler and
`netdisco-do`, and a web route's check does not protect the others. Keep
these rules when adding an action.

- **Some actions are `netdisco-do` only.** `Util/JobAction.pm` lists the
  actions the web and API refuse to queue (`xt/88-job-action-refusal.t`).
  A new action that exposes configuration, credentials or the database
  goes in that list.
- **A job field must never reach configuration without the admin check.**
  `port` and `subaction` can carry configuration overrides
  (`apply_config_overrides` in `Backend/Job.pm`). Routes that queue for
  non-admins refuse them with `carries_config_overrides`
  (`xt/102-config-overrides-need-admin.t`). Configuration decides which
  devices the backend contacts, with which credentials, and what it runs,
  so changing it is an administrator's right, whichever route the job
  came through.
- **Who may queue what** is decided by the queuing route:
  `Web/AdminTask.pm` (`nonadmin_actions`), `Web/PortControl.pm` and
  `Web/API/Queue.pm` (the `port_control` role). A new route that queues
  checks the user itself.
- **A port write also checks permission in its own check phase,** against
  the job's `username`, with the `port_acl_*` helpers in `Util/Port.pm`,
  as `PortControl.pm` does. A new write action does the same.

## Status values

`Worker/Status.pm` defines them; `JobQueue/PostgreSQL.pm` shows what each
does to the queue.

- **`done`:** the action did what it is for; its message becomes the job
  log. Store workers record `last_arpnip` or `last_macsuck` only on
  `done`.
- **`info`:** finished or skipped, but not the action's result: nothing to
  do, or rows kept after a short walk.
- **`defer`:** in new code, only when the worker failed to connect to the
  device or has no credentials for it. Deferrals count against the
  device and can hold back every action on it.
- **`error`:** something that should not happen. It outranks every other
  status, so one error becomes the job's result.
- Write messages for the operator reading the job queue: name the device,
  what was read and what was kept. Log detail at `debug`, and use
  `warning` only for something an operator must act on.

## SNMP transport

- **`reader_for($device)`** (`Transport/SNMP.pm`) returns one SNMP::Info
  object per device, shared by every worker in the job. A failed connect
  is cached too. On undef, return `defer`.
- **Table methods return what was read before a walk ended**
  (`IncompleteWalk => 'partial'`); the worker decides what that means.
- **`writer_for` is itself an SNMP SET:** its connection test writes
  `sysLocation` back. Only user actions call it. Never call it from
  discover, macsuck, arpnip or any other read.

## SNMP contexts

Some devices serve a table only in a separate SNMP context, per VLAN, MST
instance or VRF. SNMP::Info (3.983000 on) says which features need one
(`context_kinds`) and how to address each (`snmp_context`).

- **New code asks SNMP::Info** with `context_kinds` and `snmp_context`
  instead of building `community@N` itself. The existing per-VLAN path is
  `snmp_comm_reindex` in `Util/SNMP.pm`, the per-VRF one
  `snmp_vrf_context`.
- **Leave the shared session as you found it.** `update()` clears
  SNMP::Info's cache, so read what you need first, and restore the default
  context with a guard that runs however the worker exits, as
  `Macsuck/Nodes.pm` does.

## What SNMP::Info gives a worker

`Build.PL` names the SNMP::Info release Netdisco requires. Find the
release that added anything you call in SNMP::Info's `Changes`, and raise
the requirement in the same PR when needed.

- **A short walk must not clear stored rows.** Take `walk_mark($snmp)`,
  read, then call `incomplete_walks_for` naming every method whose rows
  you write. If it returns anything, write what was read and delete
  nothing. The POD in `Util/SNMP.pm` gives the message and Status to
  return; `Discover/Neighbors.pm` is the model.
- **`$snmp->error`** holds the latest error and clears when read, and
  SNMP::Info prints it only with `Debug`. Read it once and put it in your
  Status, as `PortControl.pm` does.
- **Never store or contact `0.0.0.0`.** SNMP::Info returns it as the
  address of an LLDP neighbor that has only a MAC chassis ID;
  `store_neighbors` (`Discover/Neighbors.pm`) shows how to resolve one.
- **A fix to how a device is read belongs in SNMP::Info:** fix the device
  class there (see its `AGENTS.md` and `device-class-authoring` skill),
  then require that release. Do not add vendor branches to a worker to
  correct a class.

## VRFs

Collection is off unless `store_vrfs` is on. The helpers are in
`Util/VRF.pm`, `Util/L3Domain.pm` and `Util/Device.pm`; their POD is the
contract.

- **Ask before collecting:** `vrf_collection_enabled` and
  `vrf_instances_for`. When either says no, take the existing path
  unchanged. For a device not yet stored, `vrf_collection_enabled` is
  reliable only after `reader_for`.
- **Build `vrf_skip_test` once, before a loop:** building it can cost a
  DNS lookup per key.
- **Store only VRFs read whole;** a VRF read short keeps its rows. Models:
  `store_vrf_subnets` (`Arpnip/Subnets.pm`), `gather_arps_per_vrf`
  (`Arpnip/Nodes.pm`).
- **After changing a device's `device_vrf` rows,** recompute L3 domains
  only when `l3_domain_recompute_needed` says so, after the rows are
  written.
- **To find the device an address belongs to,** use `get_device` or
  `DeviceIp->resolve_alias`. With VRFs an address can belong to several
  devices, so a search on `device_ip.alias` alone is wrong.

## SSH collectors, from the worker's side

- **`session_for($device)`** (`Transport/SSH.pm`) needs exactly one
  `device_auth` stanza left for the device and driver, naming a
  `platform`. On undef, return `defer`. Platform method shapes are in the
  SSH collector skill.
- **Never retire on a partial read.** `retire_unvouched_arps`
  (`Util/Node.pm`) decides what a CLI read vouches for; read its POD
  before changing what feeds it.

## Python worklets

- Worklets live in `share/python/netdisco/netdisco/worklet/<action>/` and
  are listed in `python_worker_plugins`; `PythonShim.pm` reads the names
  and options, and `Transport/Python.pm` runs them.
- The job reaches Python as `JobManager` (`netdisco/util/job.py`), which
  rejects keys it does not know: state the Perl side keeps per job stays
  off the job object.
- Tests and ruff settings are in `share/python/netdisco/`.

## Tests

- **Fake the transport, run the real worker.** Models:
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
- [ ] New `defer` only for connect or credential failures; Status messages
      name the device; new log lines are `debug` unless an operator must
      act.
- [ ] A short read keeps stored rows, and a test proves it.
- [ ] A new action is refused to the users who should not queue it, and a
      write checks permission in its own check phase.
- [ ] A fix to how a device is read went to SNMP::Info, or the PR says
      why not; `Build.PL` requires the release with every SNMP::Info
      method you call.
