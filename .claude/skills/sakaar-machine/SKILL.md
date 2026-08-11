---
name: sakaar-machine
description: Author a new vulnerable machine for the Sakaar cyber range - a machines/<id>/ dir with machine.yml, provision.yml, and solution.md that builds and deploys to the local libvirt lab. Use when the user asks to create, add, or design a Sakaar box/machine/challenge (a vuln + privilege escalation as a deployable VM). Encodes the engine/recipe split, the cloud-init landmines, the HTB/THM design rules, and the build+deploy+verify loop.
---

# Authoring a Sakaar machine

Read `docs/authoring.md` first for the full rationale. This skill is the
operational loop.

## Mental model

The build engine (`scripts/build.sh`) injects **networking** (name-glob DHCP)
and **flags** (opaque, per-build: `root.txt`, and `user.txt` in the
`foothold_user`'s home) into every build. The recipe you write describes **only
the challenge**. Never put `user.txt`, `root.txt`, or network config in a
`provision.yml`.

## Steps

1. **Scaffold.** Copy `machines/_template/` to `machines/<id>/`. Replace every
   `CHANGEME`. Pick a short kebab-case `id`. A `_`-prefixed dir is scaffolding
   and is ignored by the tooling, so the template never deploys.

2. **Design the vuln to the checklist** (this is what separates a real box from a
   toy):
   - Artificial vuln, not a public CVE. Recreate a developer mistake.
   - The vuln is the **only** foothold. Generate the foothold secret at build
     time and leak it *through* the vuln. Never a weak/rockyou password - it
     must not be brute-forceable over SSH. A crackable hash must fall to rockyou
     in under 5 minutes.
   - Realistic pretext. User flag then root flag, with a logical privesc.
   - Only intended services exposed. <= 2 GB RAM, <= 2 CPUs.

3. **Write `provision.yml`** avoiding the cloud-init landmines:
   - Provisioning runs **once at build**, never at deploy.
   - No `" : "` (colon-space) inside a `runcmd` string - it parses as a YAML
     dict and aborts all of `runcmd`. Put shell-with-data in a `write_files`
     script and call it.
   - No `owner: <user>` for a user cloud-init just created, and nothing written
     into `/home/<user>/` in the early pass - use `defer: true` or omit `owner`.

4. **Write `solution.md`** as the intended-path walkthrough. Do not hardcode the
   flags or the secret; they are randomised per build.

5. **Build and verify the intended path** (inside `nix develop`):
   ```
   task build MACHINE=<id>
   task deploy BOX=<id>
   task status                      # get the IP
   ```
   Then actually exploit it: trigger the vuln to obtain the foothold secret, SSH
   in with that leaked value (not a guessed one), read `user.txt`, escalate,
   read `root.txt`. Confirm both flags equal `vms/<id>/flags.txt`. If the box
   leases but a step fails, inspect the built image offline (see the cloud-init
   gotchas in `docs/authoring.md`).

6. **Tear down**: `task target:destroy BOX=<id>`.

## Done means

The box builds, leases on `sakaar-lab`, and is solvable end to end via the
intended path only, with both flags matching the engine's record. Lint stays
green: `nix flake check`.
