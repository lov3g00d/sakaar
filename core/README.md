# core - the repeatable range core

Machines in here are **persistent infrastructure**, not challenges. `task up`
builds them (once), deploys them onto the isolated lab network as
`sakaar-core-<id>`, and snapshots a clean baseline. They stay live while
challenge machines under `machines/` come and go. This persistent core is what
makes Sakaar an arena rather than a pile of isolated boxes.

A core machine is authored exactly like a challenge machine (a `machine.yml`
plus a `provision.yml`), with two differences:

- **No flags.** The build engine does not inject `user.txt` / `root.txt`, and
  there is no `foothold_user`. Core machines are never the objective.
- **`role: core`** in `machine.yml`, for clarity.

The engine still injects the name-glob DHCP networking, so a core machine leases
on `sakaar-lab` after deploy just like a target.

## Machines

| id | what it is |
|----|------------|
| `bastion` | The range portal: an nginx page that orients a player (how to play, the flag format, the beginner curriculum). Reachable from Kali at its lab IP. |

Lifecycle: `task up` (stand up), `task core:reset` (revert to clean),
`task core:rebuild` (rebuild from recipe), `task core:destroy` (remove).
