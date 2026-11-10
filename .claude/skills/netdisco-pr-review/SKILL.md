---
name: netdisco-pr-review
description: Use when reviewing a Netdisco pull request, your own before opening it or someone else's, including checking that it is current with master, that its numbers and Changes entry are right, and that each finding is verified before it is reported.
---

# Reviewing a Netdisco pull request

A review answers three questions: does the PR change only what it says,
does it break anything already on `master`, and does it follow the rules
for the area it touches. Read `AGENTS.md` first, then the skill for each
area the diff touches:

| The diff touches | Read |
|---|---|
| `share/views/`, `share/public/`, `lib/App/Netdisco/Web/` | `netdisco-frontend` |
| `share/schema_versions/`, `DB/Result/`, `DB/ResultSet/`, rows a worker writes | `netdisco-database` |
| `Worker/`, `Backend/`, `JobQueue/`, `Transport/` | `netdisco-backend` |
| `SSHCollector/Platform/`, `xt/data/sshcollector/` | `netdisco-ssh-collector` |

Each of those skills ends with a checklist. Run it against the PR.

## First: is the PR what it says

- **Compare with the merge base, not with your checkout:**
  `git diff origin/master...HEAD --stat`. Every file listed should be one
  the PR means to change. A file the description does not explain is the
  first thing to read.
- **Look for reverted work.** A file copied from an installed release or
  an older checkout silently undoes every change made to it since. For
  each changed file, `git log -10 origin/master -- FILE` lists its recent
  changes; the PR's diff must not remove what they added. The tests
  guarding those changes usually fail too, so run the area's tests.
- **No checks on the PR at all** usually means a merge conflict with
  `master`, or a first-time contributor whose run waits for approval.
  `gh pr view N --json mergeStateStatus` tells them apart.

## Numbers that collide

Two open PRs can each be fine and still not both merge.

- **Schema steps:** a new
  `share/schema_versions/App-Netdisco-DB-<N>-<N+1>-PostgreSQL.sql` and
  `$VERSION` in `lib/App/Netdisco/DB.pm`. Search the other open PRs for
  the same step number.
- **Test numbers:** a new `xt/NN-*.t` must not reuse a number on `master`
  or in another open PR. A duplicate does not fail CI.
- **Advisory lock classes:** a new `pg_advisory_xact_lock` class must not
  reuse one in `lib/` or another open PR.

## Tests

- Run the changed area's tests with `prove -Ilib`, then the whole suite
  with `prove -Ilib -j$(nproc) xt/`. `./Build test` tests `blib/`, which
  can be stale, so it can pass a broken tree.
- Do not add `-Ixt/lib`: CI does not, so a test that needs it must say
  `use lib 'xt/lib'` itself.
- **A skipped test is not a pass.** Tests that need PostgreSQL skip
  without one. If the PR changes a query or a schema step, check whether
  it was run against a database, and which PostgreSQL versions.
- A new `xt/js` test must be listed by name in
  `.github/workflows/frontend-tests.yml`, or CI never runs it.
- A fix should come with a test that fails without it. Revert the fix
  locally and run the test to see that it does.

## The rules most often missed

- **Access:** every new route declares `require_login` or `require_role`.
  Web code reads device data through `schema(vars->{'tenant'})`.
- **Jobs:** a new action that only the backend host should run is refused
  to the web and API; a job field never reaches configuration without the
  admin check; a write checks permission in its own check phase
  (`netdisco-backend`, Job permissions).
- **Short reads:** a worker that deletes rows must not do so after an
  incomplete walk or a partial CLI read.
- **API responses:** a renamed or removed key breaks clients and needs to
  be called out.
- **Templates:** a change to a shipped template that sites may have copied
  needs a `checksitelocal` rule (`netdisco-frontend`).
- **Settings:** a new setting has a default in `share/config.yml`, and the
  PR says what its documentation should say.
- **Schema steps:** never edit a shipped step; new steps are safe to run
  again and run on the oldest supported PostgreSQL (`netdisco-database`).
- **`Changes`:** an entry goes under the unreleased block at the top, as
  `* #NNNN <PR title>`. An entry under a released block is filed with that
  release.
- **Release files:** `$VERSION` in `lib/App/Netdisco.pm`, `META.json`,
  `META.yml` and `MANIFEST` are not edited in a PR. A new file that must
  not ship has a `MANIFEST.SKIP` line.

## Verify before you report

Report only what you have confirmed.

- **Treat each candidate as unverified,** however it was found. Confirm
  it by reading the code path end to end, or reproduce it: a failing
  test, a query against a scratch database, a job run with
  `netdisco-do ACTION -d DEVICE -D`.
- **Check whether it is already handled or documented.** Many apparent
  bugs are a stated trade-off in a POD section or a test's header
  comment. Read those before reporting.
- **Separate bugs from design questions.** "This returns the wrong row"
  is a bug. "This could also cover X" is a question for the author, and
  belongs in a separate list.
- **Re-check after a fix.** A fix can be right and still miss a second
  path to the same failure.

## Writing the review

- One finding per comment: where (`file:line`), what goes wrong, the
  input or state that triggers it, and the evidence (the test, query or
  log line that shows it).
- Keep it short. Do not restate the diff or explain the code back to its
  author.
- A security problem is reported privately, as `SECURITY.md` says, never
  in a public review or issue.
- Say what you checked and how, including what you did not run (no
  database, no live device), so the author knows what is still open.
