# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Netdisco is a web-based network management tool (Perl + a little Python). It discovers devices via SNMP/CLI/APIs, stores IP/MAC/topology data in PostgreSQL, and exposes a web UI and CLI. Three runtime pieces share this one codebase:

- **Web frontend** — Dancer (v1, classic — not Dancer2) app under `lib/App/Netdisco/Web/`, Template Toolkit views in `share/views/`.
- **Backend daemon** — a job queue/worker system (`lib/App/Netdisco/Backend/`, `lib/App/Netdisco/Worker/`) that runs discovery/collection jobs against devices.
- **CLI** — scripts in `bin/` (e.g. `netdisco-do`) for ad hoc job runs and admin tasks.

All three load configuration and DB schema from the same `lib/App/Netdisco/DB.pm` / `App::Netdisco::Environment`.

## Commands

This is a `Module::Build`-based Perl distribution (`Build.PL`, not `Makefile.PL`). There is no local `localenv`/`Build` in a fresh checkout — those come from the netdisco Docker dev/build image, which is what CI uses.

```sh
perl Build.PL              # generate the Build script
./Build test                # run default test suite
./Build test --test_files xt/          # run the full xt/ test suite (what CI runs)
./Build test --test_files xt/NN-name.t  # run a single Perl test file
```

Frontend JS tests use Node's built-in test runner (Node 22), not Jest — there is no test config file, no `npm test`, and no `package.json` scripts (`package.json` there is just a manifest of vendored frontend libs, not a build step):

```sh
node --test xt/js/portsort.test.js
node --test xt/js/view-templates.test.js
node --test xt/js/netmap-loading.test.js
node --test xt/js/netmap-legend.test.js
node --test xt/js/netmap-autosave.test.js
```

Always name the specific `.t` / `.test.js` file rather than globbing — `node --test` exits 0 on a glob that matches nothing, so a moved/renamed test file can silently stop running (see comments in `.github/workflows/frontend-tests.yml`).

CI (`.github/workflows/build-and-publish.yml`) runs inside the `netdisco/netdisco:latest-backend` container image and invokes tests via `localenv perl ./Build.PL` then `localenv ./Build test --test_files xt/`; there's a separate `.github/workflows/frontend-tests.yml` for the Node tests above.

## Test layout (`xt/`)

- `xt/*.t` — Perl tests, numbered by area (`10-sort_port.t`, `20-checkacl.t`, `40-template-snapshots.t`, etc). Many are narrow regression guards for a specific past incident — read the comment block at the top of a test before changing it; they often explain *why* the check is scoped the way it is (see e.g. `xt/39-html-escaper.t`).
- `xt/lib/` — test-only Perl support code, including fake worker plugins under `App::NetdiscoX::Worker::Plugin::*` used to exercise the plugin loader.
- `xt/js/` — Node `node:test` files covering vendored/hand-written frontend JS in `share/public/javascripts/`.
- `xt/snapshots/` — golden HTML snapshots of Template Toolkit views, checked by `xt/40-template-snapshots.t`. Regenerate via `xt/bin/regenerate-snapshots` when a template change is intentional.
- `xt/bin/regenerate-portsort-corpus` — regenerates the port-name sorting test corpus.

When a test's history matters (e.g. it says "ported from a QUnit page removed in commit X"), check that commit before inventing new cases — it's often the actual spec.

## Architecture

### Config and environment

- `share/config.yml` ships the defaults and is **never** edited directly (it says so at the top) — deployment overrides go in `~/environments/deployment.yml` (a Netdisco home dir, not this repo). `lib/App/Netdisco/Environment.pm` and `lib/App/Netdisco/Configuration.pm` resolve `NETDISCO_HOME` and layer config files.
- `lib/App/Netdisco/DB.pm` is the `DBIx::Class::Schema` root. Schema migrations are plain numbered SQL files in `share/schema_versions/App-Netdisco-DB-<from>-<to>-PostgreSQL.sql`, applied via `App::Netdisco::DB::SchemaVersioned`.

### Worker/job plugin system (backend)

This is the part most non-web feature work touches. Jobs (`App::Netdisco::Backend::Job`) have an `action` (e.g. `discover`, `macsuck`, `arpnip`). `App::Netdisco::Worker::Loader::load_workers` loads every configured worker plugin whose package matches `::Plugin::<action>` (or `::Plugin::Internal`), from `worker_plugins` / `extra_worker_plugins` in config; an `X::Foo` name maps to `App::NetdiscoX::Worker::Plugin::Foo` for site-local plugins outside this dist.

Plugins register via `register_worker` (`lib/App/Netdisco/Worker/Plugin.pm`), declaring a `phase` (`check` / `early` / `main` / `user` / `store` / `late`) and a `priority` (drivers get priority from `driver_priority` config). `App::Netdisco::Worker::Runner` drives a job through the phases in order, handling per-device auth (`device_auth` config, filtered/reordered per device via ACLs and `device_auth_tag_hint`) and Python worklets (`enable_python_worklets` → `App::Netdisco::Worker::Plugin::PythonShim` → `App::Netdisco::Transport::Python`, which shells out to a long-lived Python subprocess; worklets live in `share/python/`).

Concrete action plugins live in `lib/App/Netdisco/Worker/Plugin/<Action>.pm` (and a same-named subdirectory for `::namespace` sub-plugins, e.g. `Vlan/`, `Nbtstat/`). SNMP/device-model logic itself is largely `SNMP::Info` (external CPAN dep), not reimplemented here.

### Web app

`lib/App/Netdisco/Web.pm` is the Dancer app entry point; it monkeypatches a few core Dancer subs (redirect, error rendering, `uri_for`, `path`) early to add multi-tenant (`/t/<tenant>`) URL support and JSON-shaped errors for API requests — check there first if routing/redirect behavior looks unexpected.

Feature areas register themselves as **web plugins** (`web_plugins` in config, e.g. `Report::PortVLANMismatch`, `AdminTask::DuplicateDevices`) through `lib/App/Netdisco/Web/Plugin.pm`, which exposes `register_template_path`, plus shared state (`_navbar_items`, `_search_tabs`, `_device_tabs`, `_admin_tasks`, `_reports`, etc) that plugins push into to extend the UI without editing core routes. Concrete plugins live under `lib/App/Netdisco/Web/Plugin/{Report,AdminTask,Device,Search}/`.

Views are Template Toolkit under `share/views/{layouts,ajax,sidebar}/...`, mirroring the same `device/report/search/admintask` groupings. Pages are loaded with htmx (see recent history) rather than full client-side routing. Frontend JS is vendored/hand-rolled under `share/public/javascripts/` (see `package.json` for the vendored library manifest — it's documentation only, nothing installs from it) — always check `xt/js/` for existing coverage before changing a `.js` file there.

### DB layer

`lib/App/Netdisco/DB/Result/*.pm` are `DBIx::Class` result classes (one per table, e.g. `Device.pm`, `DevicePort.pm`, `Node.pm`); `lib/App/Netdisco/DB/ResultSet/*.pm` hold custom query methods. `lib/App/Netdisco/GenericDB/` is a separate, more dynamic schema layer used for user-defined/"generic" reports against arbitrary external databases (`external_databases` / `tenant_databases` config), distinct from the main app schema.

## Working conventions seen in this repo

- Perl style: `use strict; use warnings;` everywhere, heavy use of `Moo`/`Moo::Role` for new classes, `Try::Tiny` over native `eval`, `namespace::clean` after `Moo`.
- Comments in this codebase tend to record *why*, especially in tests and monkeypatches (a past incident, a constraint that isn't obvious from the code) — match that style rather than describing *what* the code does.
- Don't touch `share/config.yml` defaults casually; it's shipped config documented on the wiki (linked at the top of the file), and every key needs a corresponding default there even if real values come from `deployment.yml`.
