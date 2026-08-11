# Authoring a machine

A machine is a directory under `machines/<id>/` with three files:

| File | Purpose |
| --- | --- |
| `machine.yml` | Metadata: id, name, difficulty, base image, resources, `foothold_user`, tags. |
| `provision.yml` | The cloud-init recipe. Describes **only the challenge**. |
| `solution.md` | The intended-path walkthrough. |

Copy `machines/_template/` to start. Directories whose name begins with `_` are
scaffolding and are ignored by `task machines`, `build`, and `deploy`.

## The one rule: engine owns plumbing, recipe owns the challenge

The build engine (`scripts/build.sh`) injects the two things every machine needs
so no recipe has to reinvent them:

- **Networking.** A name-glob DHCP config, so the box leases on `sakaar-lab`
  after deploy regardless of its NIC's MAC.
- **Flags.** Opaque, unique per build. `root.txt` in `/root`, `user.txt` in the
  `foothold_user`'s home, correct permissions. The plaintext is written to
  `vms/<id>/flags.txt` (gitignored) for you to check submissions against.

So your `provision.yml` must **not** define `user.txt`, `root.txt`, or network
config. Just the vulnerability, the users, and the privesc vector.

## Design checklist (HTB/THM practice)

- **Artificial vuln, not a public CVE.** Build the flaw yourself (a bad query, a
  missing filter). Recreate a developer's mistake.
- **No unintended path.** The intended vuln must be the only foothold. Generate
  the foothold secret at build time and leak it through the vuln. Never a weak
  or rockyou-crackable password - an attacker would brute-force SSH and skip the
  vuln. If you plant a hash to crack, it must fall in < 5 min to rockyou.
- **Realistic pretext.** No `todo.txt` with the password on the webroot.
- **User then root.** A flag at the foothold and a flag at root, with a logical
  privesc between them.
- **Only intended services exposed.** Don't leave a second way in.
- **Resources:** <= 2 GB RAM, <= 2 CPUs.
- **Ship the walkthrough** in `solution.md`.

## cloud-init landmines

These each fail silently or partially. All were hit building the reference box.

- **Provisioning runs once, at build.** cloud-init keys on the seed's
  instance-id. On deploy there is no seed, so it does not re-run. Everything must
  succeed at build time.
- **`" : "` (colon-space) in a `runcmd` string** is parsed as a YAML mapping and
  aborts the whole `runcmd` (`Unable to shellify type 'dict'`). Put shell logic
  with data in a `write_files` script (literal `|` block) and call it.
- **`owner: <user>`** on a `write_files` entry for a user cloud-init creates in
  the same config fails (`getpwnam ... not found`) and aborts the remaining
  entries. Writing into `/home/<user>/` before the final stage fails for the
  same reason. Use `defer: true`, or omit `owner` (root:root 0644 is readable).

## Build and verify

Everything runs **inside `nix develop`** (that is what puts `task`, `virsh`, and
`yq` on `PATH` and sets `LIBVIRT_DEFAULT_URI`).

```
task build MACHINE=<id>     # cloud-init provisions, engine injects flags
task deploy BOX=<id>        # import onto the isolated lab net
task status                 # find the DHCP IP
```

Then verify the **intended path** end to end: exploit the vuln to obtain the
foothold secret, log in, read `user.txt`, escalate, read `root.txt`, and confirm
both match `vms/<id>/flags.txt`. Tear down with `task target:destroy BOX=<id>`.

To offer this workflow to Claude, use the `sakaar-machine` skill.
