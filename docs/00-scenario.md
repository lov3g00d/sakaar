# The Sakaar arena

Sakaar is a **persistent arena** you stand up once and keep live, then throw
rotating challenge machines into. That is the deliberate contrast with a
collection of independent labs: the network, the attacker, and the core
infrastructure are always there; only the targets change.

## Topology

```
Host (KVM/libvirt)
  └─ network sakaar-lab   (isolated, no route off-net, DHCP 10.10.10.0/24)
       ├─ sakaar-kali     graphical Kali attacker, dual-homed (NAT + lab net)
       ├─ sakaar-core-*   the repeatable core (persistent infrastructure)
       │     └─ bastion   the range portal
       └─ sakaar-tgt-*    rotating challenge machines, one per authored box
```

- **The core** (`core/`) is stood up by `task up` and stays live. Today it is one
  bastion, the range portal; it is fixed infrastructure and never a challenge.
- **Targets** (`machines/`) are built from recipes and deployed on demand with
  `task deploy`. Each is a self-contained vulnerable box with a user flag and a
  root flag.
- The network is flat for now: everything shares `sakaar-lab`. A segmented
  internal network reached by pivoting through the bastion is a later addition,
  not a beginner's first hour.

## Naming

| Domain | What it is |
|--------|-----------|
| `sakaar-kali` | the attacker |
| `sakaar-core-<id>` | a persistent core machine (from `core/<id>/`) |
| `sakaar-tgt-<id>` | a deployed challenge machine (from `machines/<id>/`) |
| `sakaar-build-<id>` | a transient build domain, undefined when the build finishes |

Machine ids are unique across `core/` and `machines/` (both share `vms/<id>/`).

## Name resolution

The lab network has a DNS domain (`sakaar.lab`), and the resolver on the gateway
(`10.10.10.1`) answers for every machine holding a lease. Boxes on the lab net
use it automatically, so from one box you reach another by name: `web-backup` or
`web-backup.sakaar.lab`, not its IP.

The dual-homed Kali attacker keeps the NAT network as its primary resolver, so
it does not resolve lab names out of the box. To attack targets by name from
Kali, point it at `10.10.10.1` for the `sakaar.lab` domain (split DNS).

## Beginner-first curriculum

Sakaar is built to be a gentle on-ramp: every box teaches one or two named
classes, ships a walkthrough in `solution.md`, and maps to a public learning
guide. The roadmap, tiered by difficulty:

| Tier | Classes | Status |
|------|---------|--------|
| Intro | enumeration, exposed services, reading a leaked secret | `web-backup` |
| Easy (web) | one box per OWASP Top 10 category (A01 IDOR, A03 injection, A05 misconfiguration, A06 outdated component, ...) | `web-sqli` = A03, `web-backup` = A05 |
| Easy (privesc) | sudo/GTFOBins, SUID, cron, LXD/docker group | `web-sqli` (sudo find), `web-backup` (cron) |
| Medium | command injection + race, NoSQL, SSRF, LFI chains | roadmap |
| Network-service | NFS, rsync, SMB anonymous, memcached, SNMP -> RCE | roadmap |

Boxes are built **to the vulnerability class**, never cloned from a specific
public machine (see `docs/authoring.md`). The curriculum is built around
standard, well-documented classes (the OWASP Top 10 for web, the common Linux
privilege-escalation and network-service classes); the tiers and the boxes are
this repo's own.
