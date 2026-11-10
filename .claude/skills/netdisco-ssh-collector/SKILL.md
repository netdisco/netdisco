---
name: netdisco-ssh-collector
description: Use when writing, changing or reviewing an SSH collector platform under lib/App/Netdisco/SSHCollector/Platform, its command output parsing, its fixtures under xt/data/sshcollector, or the tests that drive it.
---

# Writing a Netdisco SSH collector

An SSH collector reads a device over its CLI where SNMP falls short. It
lives in Netdisco itself, one Moo class per platform under
`lib/App/Netdisco/SSHCollector/Platform/`, chosen by the `platform` key of
a `device_auth` stanza (`Transport/SSH.pm` loads
`App::Netdisco::SSHCollector::Platform::<platform>`). The worker side,
including `defer` on a failed session, is in
`.claude/skills/netdisco-backend/SKILL.md`.

The rule behind everything below: a collector vouches only for what it
read whole. A parser that turns a timeout, a truncated page or an error
into "nothing there" makes Netdisco retire live data.

## Before you write a parser

- **Capture first.** Write or change a parser only against real output
  captured from the device and OS version it targets, and name them in
  the PR. A collector without a capture keeps its current behavior.
- **Prefer structured output:** `| json` where the platform has it, then
  `| display xml` (Junos), then text. Use text only where a capture shows
  no structured form, and say so in the platform's POD. EOS reads JSON
  throughout; NX-OS's per-VRF reads use `| json`; IOS-XR, IOS-XE and VOSS
  have no structured form for these commands and are parsed as text.
- **Prefer a command that names what each row belongs to.** NX-OS
  `show ip arp vrf all | json` does not name the VRF per row, so the
  collector lists the VRFs (`show vrf | json`) and reads each by name.

## Methods and return shapes

Methods are called as `$platform->method($host, $ssh, $auth)`; the
transport skips any the platform lacks. Document each return shape in the
platform's POD.

- `arpnip`: a list of `{ ip, mac }`.
- `macsuck`: `{ VLAN => { PORT => { MAC => COUNT } } }`.
- `subnets`: a list of CIDR strings.
- `arpnip_by_vrf`: `{ entries => [ { ip, mac, vrf } ], vrf_read =>
  { VRF => 0|1 }, vrf_list_complete => 0|1, families => [4, 6] }`, or
  undef when nothing was read. The contract is the comment above
  `gather_arps_by_vrf_cli` in `Arpnip/Nodes.pm`.
- `subnets_by_vrf`: `{ VRF => [ { prefix, len } ] }`, or undef.
- **A subclass that overrides `arpnip` or `subnets` must override the
  `_by_vrf` method too**, or with `store_vrfs` on the inherited one runs
  instead of its own.
- Name VRFs as Netdisco stores them (`netdisco_vrf`: `''` for the default
  table), and normalize MACs the way `store_arp` does
  (`NetAddr::MAC`), since each vendor prints them differently.

## What "read whole" means

A command's output is whole only when all of these hold:

- it returned to the anchored prompt (or, on an exec channel, the
  command exited);
- it printed no error line (`%` lines, "does not exist", "Invalid");
- every line parsed, or is a known non-row line (headers, blank lines);
- the footer matched, where the platform prints a count or total.

Then:

- **`vrf_read` is 1 only when that VRF was read whole for every family in
  `families`.** Absent or malformed `families` means IPv4 only, so a
  platform that does not say never vouches for IPv6. Read IPv6 per VRF
  only where a capture shows a working command.
- **Empty is not unknown.** A VRF list that returned to the prompt with no
  rows is a whole, empty list. Empty output for a VRF name the device
  listed is unread (0), never "empty". A count of zero, where the platform
  prints one, is a whole, empty VRF.
- **A protocol the device says a VRF lacks is whole and empty.** NX-OS's
  `show vrf` Protocols column shows whether a VRF has IPv6; for one
  without, send no IPv6 command.
- **A global table that also lists VRF hosts** (IOS XR's
  `show ipv6 neighbors`) marks its entries `mixed => 1`, so the worker can
  drop the default-table copy of a host a VRF also holds.

## Talking to the device

- **Exec channel or pty.** `$ssh->capture($command)` runs one command on
  its own exec channel, with no pager and no prompt to match; check
  `$ssh->error` after each. Where the platform needs an interactive
  session, `$ssh->open2pty` with Expect (`IOSXR.pm`, `IOSXE.pm`, `VOSS.pm`)
  must turn the pager off first (`terminal length 0`,
  `terminal more disable`, or `| no-more` per command).
- **Anchor the prompt on a capture, and test it against the capture.**
  Two prompts were wrong for a long time: IOS-XR's `qr/# +$/` never
  matched XRd, which prints `#` with no trailing space (three 10 second
  timeouts per run, and entries survived only because Expect copies its
  buffer on timeout); and `^\S+#\s*\z` matched a banner line of just `#`,
  so the reader ran one reply behind.
- **A timeout leaves output behind.** On a real device, the partial
  output of a command that timed out arrives in front of the next
  command's output. Resynchronize to the prompt, or mark every later read
  in that session incomplete.
- **Do not rely on the device closing an exec channel.**
  `Transport/SSH.pm` builds Net::OpenSSH without `kill_ssh_on_timeout`,
  so a channel the device never closes blocks the job until the worker
  timeout. It was seen with plain `ssh` on NX-OSv, not through
  Net::OpenSSH; keep each command short and its output bounded.
- **Inactivity timeout:** Net::OpenSSH gets the stanza's `timeout`, 30
  seconds without traffic by default. A long command that prints nothing
  for that long is cut off and must count as unread.
- Keep an existing filter while a platform's commands are unchanged
  (NX-OS's `arpnip` pipes through `| inc ^[1-9]`); change commands only
  with a capture.

## Fixtures and tests

- **`Test::Netdisco::FakeSSH`** (`xt/lib`) serves scripted output from
  `xt/data/sshcollector/<platform>/`, timeouts included; its POD gives
  the fixture format. Models: `xt/198` to `xt/202` (platforms),
  `xt/197-arpnip-cli-vrf.t` (the worker contract),
  `xt/195-arpnip-retire-unvouched.t` (retirement).
- **Fixtures are real captures, cut down:** keep only the command, its
  output lines and the prompt. Remove hostnames, addresses outside the
  documentation ranges (RFC 5737, RFC 3849), running configuration and
  anything that looks like a credential. `xt/` ships in the CPAN tarball,
  so the fixtures are published.
- Test the short read as well as the whole one: a command that times
  out, an error line, a truncated table, an empty table, an unknown VRF.
  Each must come back unread (0) or undef, never as an empty whole read.

## Before you open the PR

- [ ] The parser was written against a capture, named in the PR with the
      device, model and OS version.
- [ ] Structured output is used where the platform has it.
- [ ] A timeout, an error line or a truncated table reads as unread, and a
      test proves each.
- [ ] The platform's POD documents each method's return shape and what
      "whole" means for it.
- [ ] Fixtures hold no hostnames, private addresses or configuration.
