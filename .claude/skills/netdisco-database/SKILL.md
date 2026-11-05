---
name: netdisco-database
description: Use when changing or reviewing Netdisco's database schema, a schema step file under share/schema_versions, a DBIx::Class result or result set class, or code that writes rows from a worker, including the Changes entry and test numbering such a change needs.
---

# Changing the Netdisco database

Netdisco runs on PostgreSQL. The schema is `lib/App/Netdisco/DB/` (one
DBIx::Class result class per table under `Result/`, custom queries under
`ResultSet/`), and every change to it ships as a numbered step file. Sites
upgrade by running `bin/netdisco-db-deploy`, or through the Docker image,
often skipping several releases at once.

## Before you start: numbers

- **Schema version:** a step is
  `share/schema_versions/App-Netdisco-DB-<N>-<N+1>-PostgreSQL.sql`, and
  `$VERSION` in `lib/App/Netdisco/DB.pm` becomes `N+1`. Open pull requests
  may already claim the next number. Check them and ask in the PR before
  taking one; two PRs holding the same step cannot both merge.
- **Test numbers:** as for any test (`AGENTS.md`, Tests).

## Writing a step file

- **Never edit a step that has shipped.** Sites have already run it. Fix
  forward with a new step.
- **One step per schema version**, plain DDL and data fixes. The parser
  (`App::Netdisco::DB::StepFile`) handles strings, dollar-quoted bodies and
  `BEGIN`/`COMMIT` wrappers; `xt/150-schema-step-file.t` checks every
  shipped step against it.
- **Comments go on their own lines.** No trailing `-- comment` after code:
  the older reader joins lines and the comment swallows the rest of the
  statement. `xt/150` fails a step from 101 on that has one.
- **The step runs in one transaction.** `netdisco-db-deploy` stops at a
  failing step and applies nothing from it. A statement PostgreSQL refuses
  inside a transaction, such as `CREATE INDEX CONCURRENTLY`, needs
  `-- netdisco: no-transaction` as the step's first line.
- **Steps must be safe to run again.** `netdisco-db-deploy --redeploy-all`
  replays every step on a database that already has them, and
  `--force-step` skips a step's failing statements. Use `IF NOT EXISTS` on
  `CREATE TABLE`, `CREATE INDEX` and `ADD COLUMN`, `IF EXISTS` on `DROP`,
  and `CREATE OR REPLACE` for functions and views (a view can only gain
  columns at the end). Make data fixes conditional, so a second run
  matches nothing and changes no data Netdisco or an administrator keeps.
- **Write for the oldest PostgreSQL sites run.** The startup warning in
  `App::Netdisco::Util::PostgresFloor` names the version a future release
  will require; until then older servers still deploy. Raising what a step
  needs is a maintainer decision, so say in the PR if yours needs a newer
  server.
- **Large tables:** a step that rewrites `node`, `node_ip` or `device_port`
  takes minutes on a big site and holds its locks throughout. Prefer
  changes PostgreSQL can make without a rewrite, and say in the PR what
  the step costs on a large table.
- **Adding a column with a default:** on PostgreSQL before 11,
  `ADD COLUMN ... DEFAULT` rewrites the whole table under an exclusive
  lock. Add the column bare, then set its default in a second statement,
  as step 103-104 does (`xt/166-schema-104-first-seen.t`).
- **Every index has a cost.** Before adding one, check that no existing
  index or the primary key already covers it (`xt/128` guards the cleanup
  that removed such duplicates). Each index slows every write, and an
  index on a column that changes stops PostgreSQL's cheap in-place (HOT)
  update for that row.
- **Keys:** columns in a primary key or upsert key are `NOT NULL` with a
  default. Use `''` or `0` for "none", never NULL, because NULLs never
  conflict and duplicate rows follow.

Then update the result class to match: columns, primary key, relations.

## Queries

- **Use DBIx::Class.** Query through result sets and the methods in
  `DB/ResultSet/`. Write raw SQL (`dbh_do`, a virtual view, a literal SQL
  reference) only where DBIC cannot express it, and then with bind
  parameters, never values interpolated into the string.
- **Check the plan** with `EXPLAIN` on a realistically sized database, on
  the oldest and newest PostgreSQL you support: plans differ between
  versions. Two shapes have cost real time here: a subquery where a list
  of values lets PostgreSQL use an index (`xt/138`), and a correlated
  subquery per row, which raises the planner's estimate past its JIT
  threshold and adds tens of milliseconds to every call.

## Writing rows from a worker

- **Bulk writes use the shared upsert.** Every result set has
  `$rs->upsert(\@rows, \%options)` (`App::Netdisco::DB::Upsert`): one
  `INSERT ... ON CONFLICT (primary key) DO UPDATE` per batch, writing only
  rows whose values changed. Its POD lists the options (`insert_only`,
  `touch`) and the row rules. Prefer it to delete-and-reinsert, which
  writes every row on every poll.
- **Never select, then insert.** Two pollers that see the same new row
  both insert it, and one fails on the primary key; the upsert's
  `ON CONFLICT` makes concurrent writers safe (`xt/160-subnet-upsert.t`).
- **Updating in place resets nothing.** Delete-and-reinsert cleared stale
  state as a side effect; with the upsert, anything that should disappear
  must be cleared explicitly, such as tags on ports that no longer match
  (`xt/176`), stale neighbor columns (`xt/175`) and wireless rows, which
  age out on their own `time_last` (`xt/100`).
- **`remove_unseen` is a data-loss boundary.** It deletes the rows of a
  scope that the current read did not see; its scope must name key
  columns and include the device's `ip`, or it deletes other devices'
  rows (`xt/163-db-remove-unseen.t`). Never call it after a short read.
- **Take locks in a stable order.** Two jobs that write the same rows in
  different orders deadlock. Sort rows by their key before writing, and
  keep each transaction short. Where order cannot be guaranteed, the code
  says how it avoids the deadlock (see the advisory lock in
  `App::Netdisco::Util::Node` and the per-link transactions in
  `Discover/Neighbors.pm`); read those comments before changing that code.
- **Advisory lock classes are unique numbers.** The first argument of
  `pg_advisory_xact_lock` names what is locked: `1728` is ARP entries by
  address (`App::Netdisco::Util::Node`). Before taking a new class, search
  `lib/` and open pull requests for `pg_advisory`, keep the number in a
  named constant with a comment, and use the `_xact_` form so the lock ends
  with its transaction.
- **Do not open a database connection before the backend forks.** Code that
  runs at load time or in the backend's startup checks must not query. A
  handle opened in the parent can be cached into every worker, and two
  processes then share one connection.
- **A short read must not delete.** When SNMP or SSH returns less than a
  full table, keep the stored rows rather than treating the missing ones
  as gone. Workers check this with `walk_mark` and `incomplete_walks_for`
  (`App::Netdisco::Util::SNMP`).
- **Timestamps:** build them the way the workers already do (the forms the
  upsert accepts are listed at the top of `DB/Upsert.pm`). A hand-built
  string that sorts differently breaks the retirement logic that compares
  them.

## Tests

- Tests that need a database connect through the normal configuration and
  skip when none is reachable (see the top of `xt/54-ports-node-stitch.t`).
  A skip is not a pass: say in the PR whether yours ran against a real
  database, and which PostgreSQL version.
- Most database code is tested without a database: build the SQL with
  `as_query` on an offline schema and assert it, or replace `upsert` and
  `remove_unseen` with recorders and run the real worker (`xt/167` to
  `xt/176`). CI runs these, unlike the tests that need PostgreSQL.
- A new step: add a test that the step file parses and that the result
  class matches it, beside `xt/150` and `xt/166-schema-104-first-seen.t`.

## Changes and the PR

- `Changes` keys on the version at the top of each block. An entry under a
  block that has already been released is filed with that release, and a
  heading that is not a real version number is dropped. Put the entry
  under the unreleased block at the top, `* #NNNN <PR title>`, or leave it
  for the maintainer.
- A schema change needs `netdisco-deploy` on upgrade. Say so in the entry
  the way earlier ones do: `(database schema 104: run netdisco-deploy)`.
- Say in the PR body which schema number and test numbers you took, the
  PostgreSQL versions you tested, and what the step costs on a large site.
