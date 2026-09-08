# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Sakaar is a local, libvirt-native cyber range: a graphical Kali attack box plus
build-your-own vulnerable target VMs on an isolated KVM network. It is not a
VulnHub importer (that was dropped). Targets are authored in-repo as cloud-init
recipes and built deterministically from official base cloud images.

It is a **persistent arena**, not a set of independent labs: `task up` stands up
a repeatable core (the network, Kali, and persistent infrastructure under
`core/`) that stays live, and challenge machines under `machines/` are deployed
into it on demand. See `docs/00-scenario.md` for the topology and the
beginner-first curriculum.

## Working in this repo

Everything runs inside `nix develop`. That is what puts `task`, `virsh`, `yq`,
`cloud-localds`, etc. on `PATH` and exports `SAKAAR_ROOT` and
`LIBVIRT_DEFAULT_URI=qemu:///system`. Commands assume that shell.

- `task` lists all tasks (the entry point; Taskfile.yml delegates to scripts/).
- `task doctor` is a read-only host preflight (KVM, libvirtd, tooling). It never mutates the host.
- `task lint` is the full check suite, running `nix flake check`: shellcheck on scripts/, nixfmt on flake.nix, yamllint on config/ and machines/, statix + deadnix on the Nix. CI runs exactly this. Run it before finishing any change.
- `task fmt` formats Nix (`nixfmt`) and shell (`shfmt -w -i 2 -ci`).

Lab lifecycle: `task up` (network + Kali + persistent core), `task down` (stop
attacker + core), `task reset` (revert the whole arena to clean), `task machines`
(authored machines + state), `task build MACHINE=<id>`, `task deploy BOX=<id>`,
`task status`, `task target:{start,stop,reset,destroy,console} BOX=<id>`,
`task core:{reset,rebuild,destroy}`.

There is no test framework. Correctness is proven by building a machine and
walking its intended path end-to-end against the deployed VM (see
docs/authoring.md, "Build and verify").

## Architecture

All logic lives in Bash under `scripts/`, sourced from a shared `common.sh`.
The Taskfile is a thin dispatcher. libvirt (`qemu:///system`) is the substrate;
`yq` reads all YAML config.

- **common.sh** is sourced by every script (never executed). It holds the
  `ROOT`/`VMS`/`MACHINES` paths, the `LIBVIRT_DEFAULT_URI` export, colors,
  `die`/`msg`/`step`, a resumable `download`, `yqf`/`lab` YAML readers, and the
  machine helpers (`mach_dir`, `mach_get`, `is_machine`, `mach_ids`).
  `_`-prefixed machine dirs are scaffolding and are skipped everywhere.
- **lab.sh** defines/starts `sakaar-lab`, an isolated (no `<forward>`) DHCP
  network, 10.10.10.0/24. Targets get a lease but no route out.
- **attacker.sh** imports the official prebuilt Kali qcow2, dual-homed on the
  NAT `default` net (updates) and `sakaar-lab` (attacking). It verifies the
  SHA256 from config/lab.yml.
- **build.sh** is the deterministic build engine. It copies a base cloud image,
  generates a cloud-init seed, boots it once on the NAT net, waits for
  self-poweroff, and undefines the build domain, yielding `vms/<id>/box.qcow2`.
  It builds both challenge machines (`machines/`) and core machines (`core/`),
  resolving the recipe dir by id; only challenge machines get flags injected.
- **target.sh** deploys built qcows onto `sakaar-lab` (domain `sakaar-tgt-<id>`),
  snapshots a `clean` baseline on deploy, and runs the lifecycle. `reset` is a
  snapshot-revert; IPs come from DHCP leases matched by NIC MAC (`lease_ip` in
  common.sh). `reset-all` reverts every deployed target.
- **core.sh** owns the persistent core: `task up` builds (if needed), deploys,
  and snapshots each `core/<id>/` machine as `sakaar-core-<id>`, and it stays
  live across target churn. Same build path as challenge machines, minus flags.
- **config/lab.yml** is the single source of truth for the network, the Kali
  image (url + sha + resources), and the base cloud images machines build from.

### The engine/recipe contract (the core design rule)

A machine is `machines/<id>/` with `machine.yml` (metadata), `provision.yml`
(cloud-init recipe), and `solution.md` (walkthrough). The split is strict:

- **The engine owns plumbing.** `build.sh` injects DHCP networking (matched by
  NIC *name* glob `e*`, not MAC, because the deployed box's different MAC would
  otherwise never lease) and the flags. Flags are opaque and unique per build:
  `root.txt` (root-only) and `user.txt` (into `foothold_user`'s home,
  `defer: true` so it lands after cloud-init creates that user). Plaintext is
  written to `vms/<id>/flags.txt` (gitignored) for checking submissions.
- **The recipe owns only the challenge.** `provision.yml` must NOT define
  `user.txt`, `root.txt`, or network config; the engine adds them. It describes
  the vulnerability, users, and privesc vector only.

When editing `build.sh`'s `inject_flags`, preserve two non-obvious invariants
already encoded there (both cost real debugging): use `head -c N | od`, not
`tr | head` (SIGPIPE under `pipefail` aborts the build), and keep `user.txt` on
`defer: true`.

**Core machines** (`core/<id>/`) are the same recipe shape but are persistent
infrastructure, not challenges: no `foothold_user`, `role: core`, and the engine
skips flag injection for them. See `core/README.md`.

### cloud-init landmines (documented in docs/authoring.md)

These fail silently or partially, so respect them when writing or reviewing
recipes: provisioning runs once at build time (no re-run on deploy, so
everything must succeed at build); a `" : "` (colon-space) inside a `runcmd`
string is parsed as a YAML mapping and aborts the whole `runcmd`, so put
shell-with-data in a `write_files` script and call it; `owner: <user>` (or
writing into `/home/<user>/`) before the final stage fails `getpwnam` and aborts
the remaining entries, so use `defer: true`.

## Authoring machines

`docs/authoring.md` is the authoritative guide and encodes the HTB/THM design
rules (artificial vuln not a public CVE, no unintended path, generate the
foothold secret at build and leak it through the vuln, never a rockyou-crackable
SSH password, user-then-root, 2 GB / 2 CPUs max). The `sakaar-machine` skill
drives the author, build, deploy, verify loop. Reference machine:
`machines/web-sqli/`.

## Conventions

- Shell: `shfmt -i 2 -ci`, `set -euo pipefail` (via common.sh), targets addressed
  explicitly (`virsh --domain`, exact refs) rather than via a global default.
  All scripts must pass shellcheck.
- Keep libvirt calls scoped to `qemu:///system`; VMs never touch the session daemon.
- `vms/` (built images, base images, flags) is gitignored working state, not committed.
