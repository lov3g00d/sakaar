# Sakaar

<p align="center">
  <img src="assets/sakaar-banner.png" alt="Sakaar - a local cyber range" width="100%">
</p>

A local, **libvirt-native** cyber range: a graphical Kali attack box, a
persistent core of range infrastructure, and build-your-own vulnerable target
VMs, all on an isolated KVM network. Think a self-hosted, offline HTB/THM.
Sakaar is the arena; the targets are the contenders you throw into it.

## Authorization and safety

Everything here is for **local, authorized training against the deliberately
vulnerable machines that are part of this lab**. Target VMs run on an isolated
libvirt network (`forward_mode: none`) with **no route to your LAN or the
Internet** — only the Kali attacker (dual-homed) can reach them. Do not point any
of this at systems you do not own.

## How it works

```
Host (KVM/libvirt)
  └─ network sakaar-lab   (isolated + DHCP, 10.10.10.0/24)
       ├─ sakaar-kali     graphical XFCE, dual-homed (NAT for updates + lab net)
       ├─ sakaar-core-*   the persistent core (range portal), always up
       └─ sakaar-tgt-*    challenge machines, built from recipes, deployed on demand
```

- **Kali** is the official prebuilt qcow2 (full desktop) imported into libvirt.
- **The core** (`core/`) is persistent infrastructure that `task up` stands up
  and keeps live. It is what makes Sakaar an arena rather than a pile of boxes.
- **Targets** (`machines/`) are authored in-repo as cloud-init recipes and built
  deterministically from official base cloud images (no external box mirror).
- **Reset** is an instant libvirt snapshot revert, per box or across the arena.

## Prerequisites

**Host (you provide, once):** [Nix](https://nixos.org) with flakes, hardware
virtualisation + `/dev/kvm`, and `libvirtd` enabled. On NixOS:
`virtualisation.libvirtd.enable = true;` + add your user to the `libvirtd`
group. `task doctor` checks all of this.

**Project tooling (the flake provides):** `virt-manager`/`virt-install`,
`virt-viewer`, `libvirt` (virsh), `qemu` (qemu-img), `p7zip`, `fzf`, `yq`, `jq`,
plus linters. No global installs.

## Quick start

```bash
git clone <repo> sakaar && cd sakaar
nix develop

task doctor            # host preflight
task up                # lab network + Kali + persistent core (first run downloads Kali)
task attacker:console  # open the Kali desktop  (login: kali / kali)

task machines                 # authored machines and their build/deploy state
task build  MACHINE=web-sqli  # build a machine from its recipe
task deploy BOX=web-sqli      # deploy it onto the isolated lab net (or run bare to fzf-pick)
task status                   # attacker, core, and targets with their lab IPs
```

Then attack the target from Kali by its lab IP. When done:

```bash
task target:reset   BOX=web-sqli   # snapshot back to a clean box
task target:destroy BOX=web-sqli   # remove it entirely
task reset                         # revert the whole arena (core + targets)
```

## Authoring a machine

A machine is a directory under `machines/<id>/` with three files: `machine.yml`
(metadata), `provision.yml` (the cloud-init recipe describing only the
challenge), and `solution.md` (the walkthrough). The build engine injects the
networking and the flags, so recipes never hardcode them. Copy
`machines/_template/` to start, and see `docs/authoring.md` for the full guide
and the HTB/THM design rules. Persistent range infrastructure lives under
`core/` (see `core/README.md`).

## Commands

| Command | Does |
|---|---|
| `task doctor` / `task up` / `task down` | preflight / bring up arena / stop attacker + core |
| `task machines` / `task build MACHINE=<id>` | list authored machines / build one from its recipe |
| `task deploy [BOX=id]` | deploy a built machine onto the lab net |
| `task status` | attacker, core, and targets with lab IPs |
| `task reset` | revert the whole arena to clean baselines |
| `task attacker:console` / `attacker:ssh` | graphical desktop / shell |
| `task target:start\|stop\|reset\|destroy\|console BOX=<id>` | box lifecycle |
| `task core:reset\|rebuild\|destroy` | persistent core lifecycle |
| `task net:up\|down` | lab network only |
