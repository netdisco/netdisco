# Agent instructions for Netdisco

Netdisco is a web-based network management tool in Perl, with some Python.
It discovers devices over SNMP, CLI and APIs, stores IP, MAC and topology
data in PostgreSQL, and serves a web UI, an API and a CLI.

Before changing anything under `share/views/`, `share/public/` or
`lib/App/Netdisco/Web/`, read `.claude/skills/netdisco-frontend/SKILL.md`.
Before changing the schema, a step file under `share/schema_versions/`, or
how a worker writes rows, read `.claude/skills/netdisco-database/SKILL.md`.
Before changing a worker, the job queue or a transport under
`lib/App/Netdisco/Worker/`, `Backend/`, `JobQueue/` or `Transport/`, read
`.claude/skills/netdisco-backend/SKILL.md`; before changing an SSH
collector under `lib/App/Netdisco/SSHCollector/`, read
`.claude/skills/netdisco-ssh-collector/SKILL.md`. Before reviewing a pull
request, your own or someone else's, read
`.claude/skills/netdisco-pr-review/SKILL.md`.

## How the code fits together

Three runtime pieces share one codebase, configuration and schema
(`App::Netdisco::Environment`, `App::Netdisco::DB`):

- **Web frontend:** a Perl Dancer 1 app (not Dancer2) under
  `lib/App/Netdisco/Web/`, with Template Toolkit views in `share/views/`.
  In the browser, with no jQuery anywhere (versions in `package.json`):
  - Bootstrap 5.3: CSS framework and components.
  - DataTables 3: table sorting, paging and search, used as `DataTable`
    without jQuery; examples written as `$(...).DataTable()` do not apply.
  - htmx 4: loads pages and tabs as server-rendered HTML. npm's `latest`
    is still htmx 2, and most examples online are htmx 2. htmx publishes
    its own agent skills for 4, including one for upgrading from htmx 2:
    https://github.com/bigskysoftware/htmx/tree/four/dist/skills
  The frontend skill covers how Netdisco uses them.
- **Backend:** a job queue (`lib/App/Netdisco/Backend/`) and workers
  (`lib/App/Netdisco/Worker/`) that run actions such as `discover`,
  `macsuck` and `arpnip` against devices.
- **Python worklets:** some backend workers are Python, under
  `share/python/netdisco/netdisco/worklet/`. `enable_python_worklets` and
  `python_worker_plugins` in `share/config.yml` turn them on and list them
  (for example `linter.main` and `stats.early`).
  `App::Netdisco::Worker::Plugin::PythonShim` runs them through
  `App::Netdisco::Transport::Python`, a long-lived Python process whose
  environment uv builds (`Alien::ultraviolet`,
  `share/python/netdisco/pyproject.toml`). Their tests and ruff settings
  are beside them in `share/python/netdisco/`.
- **CLI:** scripts in `bin/`, chiefly `netdisco-do` for ad hoc jobs.

Worker plugins:

- `App::Netdisco::Worker::Loader` loads every configured plugin whose
  package matches `::Plugin::<action>`, from `worker_plugins` and
  `extra_worker_plugins`. An `X::Foo` name maps to
  `App::NetdiscoX::Worker::Plugin::Foo`, for site-local plugins.
- Plugins call `register_worker` (`Worker/Plugin.pm`) with a `phase`
  (`check`, `early`, `main`, `user`, `store`, `late`) and a `driver`.
  `App::Netdisco::Worker::Runner` runs the phases in order and handles
  per-device credentials (`device_auth`).
- Device access goes through SNMP::Info, a separate CPAN distribution. A
  fix that belongs in how a device is read usually belongs there, not here.
  SSH collectors are under `lib/App/Netdisco/SSHCollector/Platform/`.

Web plugins:

- Feature areas register through `lib/App/Netdisco/Web/Plugin.pm`
  (`web_plugins` in config): device tabs, search tabs, reports and admin
  tasks. Concrete plugins live under
  `lib/App/Netdisco/Web/Plugin/{Device,Search,Report,AdminTask}/`. A
  plugin that ships its own templates adds their directory with
  `register_template_path`.
- `lib/App/Netdisco/Web.pm` monkeypatches several Dancer subs for tenant
  URLs and JSON errors. Look there first when routing or redirects behave
  unexpectedly.
- **Tenants:** a site can split its data across databases
  (`tenant_databases`). Web code reads data through
  `schema(vars->{'tenant'})`, which follows the `/t/<tenant>` URL; only
  users, logins and access control lists use `schema('netdisco')`. Code
  that names `'netdisco'` for device data shows the wrong tenant's data.
- **Every route declares its access:** `require_login`, or
  `require_role` with `admin`, `api`, `api_admin` or `setting`. A route
  without one is open to anyone.
- **API responses are a contract.** Adding a key is fine; renaming or
  removing one breaks clients, so say so in the PR.

Database:

- PostgreSQL is the only supported database (DBD::Pg, through DBIx::Class).
  Releases still run on PostgreSQL 9.6; a startup warning
  (`App::Netdisco::Util::PostgresFloor`) names 14 as the version future
  releases will require. Write for the oldest version still supported;
  the database skill covers it.
- `lib/App/Netdisco/DB/Result/` holds one DBIx::Class result class per
  table; `DB/ResultSet/` holds custom queries.
- `App::Netdisco::GenericDB` is a separate, schema-less layer that
  configured reports use to query other databases (`external_databases`).
  Tenant databases (`tenant_databases`) use the main schema.
- Schema changes are numbered SQL files in `share/schema_versions/`, and
  `$VERSION` in `lib/App/Netdisco/DB.pm` is the schema version. The
  database skill covers them.

Configuration:

- `share/config.yml` holds the shipped defaults. Never edit it to change a
  deployment; that goes in `~/environments/deployment.yml`.
- A new setting needs a default in `share/config.yml`, a section on the
  wiki's Configuration page, and, if operators are likely to set it, a
  commented example in `share/environments/deployment.yml`. The wiki is the
  documentation home; do not add POD manuals.

## Code style

- Every module starts with `use strict; use warnings;`.
- New classes use `Moo` or `Moo::Role`; error handling uses `Try::Tiny`
  rather than `eval`.
- Follow the code around you before any general preference.
- Comments say why, not what: the incident, the constraint or the
  trade-off that is not visible in the code, as the test headers do.

## Tests

Locally, one file, then the whole suite:

```sh
prove -Ilib xt/NN-name.t
prove -Ilib -j$(nproc) xt/
```

CI (`.github/workflows/build-and-publish.yml`) runs the whole suite inside
the `netdisco/netdisco:latest-backend` container:

```sh
perl Build.PL && HARNESS_OPTIONS=j$(nproc) ./Build test --test_files xt/
```

- **Run with `-Ilib` and without `-Ixt/lib`.** `./Build test` tests `blib/`,
  which can be stale, so `prove -Ilib` is the reliable check. CI does not
  put `xt/lib` on the path, so a test that needs it must say
  `use lib 'xt/lib'` itself, or it passes locally and fails in CI.
- **Tests that need a database skip without one.** A skipped test is not a
  pass. If your change touches a query, say in the PR whether it ran
  against a real database.
- **Test numbers:** `xt/` files are numbered. Pick a number no file on
  master and no open pull request uses, and say in the PR which you took.
  A duplicate number does not fail CI, so nothing else catches it.
- **Many tests guard one past incident.** Read the comment at the top of a
  test before changing it; it usually explains why the check is scoped the
  way it is. When it says the test was ported from an earlier commit, read
  that commit before inventing cases: it is often the real specification.
- **Template snapshots:** `xt/40-template-snapshots.t` compares rendered
  views with `xt/snapshots/`. After a deliberate template change, run
  `xt/bin/regenerate-snapshots` and review the diff.
  `xt/bin/regenerate-portsort-corpus` rebuilds the port-name sort corpus
  the same way.
- **`xt/lib`** holds test-only support code, including fake worker plugins
  under `App::NetdiscoX::Worker::Plugin` that exercise the plugin loader.
- **JavaScript tests** use Node's built-in runner (Node 22), one file at a
  time: `node --test xt/js/NAME.test.js`. A new `xt/js` file must also be
  added by name to `.github/workflows/frontend-tests.yml`, because
  `node --test` exits 0 on a glob that matches nothing.

**CI checks beyond the tests:**

- **Perl dependency scan** (`cpan-audit.yml`, and two steps in
  `build-and-publish.yml` on pull requests) fails when a dependency has a
  CPANSec advisory: a `Build.PL` minimum that still allows an affected
  version, an upgraded install that holds one, or a dependency with an
  advisory that Netdisco loads but `Build.PL` does not name. Fix it by
  raising or adding the minimum in `Build.PL`; on failure,
  `xt/bin/cpan-audit-fix-hints` prints what to change. Only when no
  release fixes it, or it does not apply, add the advisory to
  `.cpanauditignore` with the reason its header asks for. The scan runs
  daily against a fresh advisory database, so it can fail with no related
  change; fix that in its own pull request.
- **Frontend dependency scan** (retire.js) and
  `xt/33-vendored-manifest.t`: see the frontend skill.
- **`xt/00-compile-1.t` to `-4.t`** each compile a share of `lib/` and
  `bin/`; a failure there means a file does not compile.
- **`check-version` skipped** on a pull request is normal: it runs only
  for Dependabot's.

## Trying a change

With a database set in `~/environments/deployment.yml`:

- `bin/netdisco-web-fg` runs the web UI in the foreground.
- `bin/netdisco-backend-fg` runs the backend in the foreground.
- `bin/netdisco-do ACTION -d DEVICE -D` runs one job against one device
  with debug output.

## Before you open a pull request

- [ ] The branch starts from current `master` and is rebased onto it.
      Never copy a file from an installed release or an older checkout
      into the branch: that silently reverts every change made since.
- [ ] `git diff origin/master...HEAD --stat` lists only files you meant to
      change.
- [ ] Every test file for the area you changed passes with
      `prove -Ilib`, and the full `xt/` suite passes.
- [ ] Template changes: snapshots regenerated and reviewed. A change to a
      shipped template that a site may have copied has a `checksitelocal`
      rule (see the frontend skill).
- [ ] New settings have a `share/config.yml` default; the PR says what the
      wiki entry should say.
- [ ] Not edited: `$VERSION` in `lib/App/Netdisco.pm`, `META.json`,
      `META.yml`, `MANIFEST`. Maintainers regenerate them at release.
- [ ] A new file that must not ship (a script, notes, tooling) has a
      `MANIFEST.SKIP` line. `.gitignore` does not decide what goes into
      the release.
- [ ] `Changes`: maintainers add the entry at merge. If you add one, put
      `* #NNNN <PR title>` under the unreleased heading at the top.
- [ ] The PR body says what changed, why, and how it was verified, and
      names the issue it fixes.
- [ ] A security problem is reported privately, as `SECURITY.md` says,
      not in a public issue or pull request.

A first-time contributor's CI waits until a maintainer approves the run.
A pull request that shows no checks at all usually has a merge conflict
with `master`.
