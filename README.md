# Sakaar

<p align="center">
  <img src="assets/sakaar-banner.png" alt="Sakaar - a local cyber range" width="100%">
</p>

A local, **libvirt-native** cyber range: a graphical Kali attack box plus a
one-command spinner for vulnerable **VulnHub** target VMs, all on an isolated
KVM network. Think a self-hosted, offline HTB/THM — Sakaar is the arena, the
targets are the contenders you throw into it.

## Authorization and safety

Everything here is for **local, authorized training against the deliberately
vulnerable machines that are part of this lab**. Target VMs run on an isolated
libvirt network (`forward_mode: none`) with **no route to your LAN or the
Internet** — only the Kali attacker (dual-homed) can reach them. Do not point any
of this at systems you do not own.

## How it works

```
Host (NixOS, KVM/libvirt)
  └─ network sakaar-lab  (isolated + DHCP, 10.10.10.0/24)
       ├─ sakaar-kali    graphical XFCE, dual-homed (NAT for updates + lab net)
       └─ targets        VulnHub boxes, imported + isolated, DHCP-assigned IPs
```

- **Kali** is the official prebuilt qcow2 (full desktop) imported into libvirt.
- **Targets** are VulnHub `.ova` boxes: downloaded, `qemu-img`-converted to
  qcow2, and imported with `virt-install` (e1000 NIC for legacy compatibility).
- **Reset** is an instant libvirt snapshot revert.

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
task up                # lab network + graphical Kali (first run downloads Kali)
task attacker:console  # open the Kali desktop  (login: kali / kali)

task targets           # the box catalog
task deploy            # pick a box (fzf) - or: task deploy BOX=mr-robot
task status            # attacker + targets and their lab IPs
```

Then attack the target from Kali by its lab IP. When done:

```bash
task target:reset   BOX=mr-robot   # snapshot back to a clean box
task target:destroy BOX=mr-robot   # remove it entirely
```

## Adding boxes

Drop a file in `catalog/<id>.yml` — no central files to edit:

```yaml
id: my-box
name: My Box
url: https://download.vulnhub.com/.../my-box.ova
sha256: ""           # optional
format: ova          # ova | zip | qcow2
difficulty: easy
memory: 1024
cpus: 1
disk_bus: sata       # ide/sata/virtio - match the box (see its .ovf)
nic_model: e1000     # e1000 imports most VulnHub boxes cleanly
# fixup: '--run-command "..."'   # optional virt-customize for pinned NIC configs
```

VulnHub boxes are community snowflakes; `e1000` + the right `disk_bus` handles
most, and the optional `fixup` (via `libguestfs`) covers the rest.

## Commands

| Command | Does |
|---|---|
| `task doctor` / `task up` / `task down` | preflight / bring up / stop |
| `task targets` / `task deploy [BOX=id]` | list catalog / deploy a box |
| `task status` | attacker + targets with lab IPs |
| `task attacker:console` / `attacker:ssh` | graphical desktop / shell |
| `task target:start|stop|reset|destroy|console BOX=<id>` | box lifecycle |
| `task net:up|down` | lab network only |
