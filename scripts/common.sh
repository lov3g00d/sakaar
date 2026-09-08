#!/usr/bin/env bash
# Shared helpers for the Sakaar scripts. Source this; do not execute.
# shellcheck disable=SC2034  # many definitions here are consumed by sourcing scripts
set -euo pipefail

ROOT=${SAKAAR_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
LAB="$ROOT/config/lab.yml"
VMS="$ROOT/vms"
MACHINES="$ROOT/machines"
CORE="$ROOT/core"

# Every libvirt call targets the system daemon (where the range VMs live).
export LIBVIRT_DEFAULT_URI="qemu:///system"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' C=$'\e[36m' B=$'\e[1m' Z=$'\e[0m'
else
  G='' Y='' R='' C='' B='' Z=''
fi

die() {
  printf '%serror:%s %s\n' "$R" "$Z" "$*" >&2
  exit 1
}
msg() { printf '%s\n' "$*"; }
step() { printf '%s==>%s %s\n' "$C" "$Z" "$*"; }

# Download a URL to a destination, resuming partials and skipping when the local
# file already matches the server's size. Never leaves a truncated file that a
# later extract would choke on.
download() {
  local url="$1" dest="$2" srv=0 have=0
  srv=$(curl -sIL --max-time 30 "$url" 2>/dev/null |
    awk 'BEGIN { IGNORECASE = 1 } /^content-length:/ { v = $2 } END { print v + 0 }' | tr -d '\r')
  [ -f "$dest" ] && have=$(stat -c %s "$dest")
  if [ "$srv" -gt 0 ] && [ "$have" -eq "$srv" ]; then return 0; fi
  step "fetching $(basename "$dest")"
  # Resume partials; retry transient mirror errors (503/timeouts) with backoff.
  curl -L --fail -C - --retry 8 --retry-delay 10 --retry-all-errors -o "$dest" "$url"
}

# yq scalar read; missing/null -> empty string.
yqf() {
  local v
  v=$(yq "$2" "$1" 2>/dev/null) || v=''
  [ "$v" = 'null' ] && v=''
  printf '%s' "$v"
}
lab() { yqf "$LAB" "$1"; }

domain_state() { virsh domstate "$1" 2>/dev/null || echo "absent"; }
domain_exists() { virsh dominfo "$1" >/dev/null 2>&1; }

# Authored machines (built locally from a recipe).
mach_dir() { echo "$MACHINES/$1"; }
mach_get() { yqf "$(mach_dir "$1")/machine.yml" "$2"; }
is_machine() {
  case "$1" in _*) return 1 ;; esac # _-prefixed dirs are scaffolding, not machines
  [ -f "$(mach_dir "$1")/machine.yml" ]
}
mach_ids() {
  [ -d "$MACHINES" ] || return 0
  local d b
  for d in "$MACHINES"/*/; do
    b=$(basename "$d")
    case "$b" in _*) continue ;; esac
    [ -f "$d/machine.yml" ] && printf '%s\n' "$b"
  done | sort
}

# Core machines: persistent range infrastructure (bastions). Same recipe shape
# as challenge machines but built without flags and stood up by `task up`.
core_dir() { echo "$CORE/$1"; }
core_get() { yqf "$(core_dir "$1")/machine.yml" "$2"; }
is_core() {
  case "$1" in _*) return 1 ;; esac
  [ -f "$(core_dir "$1")/machine.yml" ]
}
core_ids() {
  [ -d "$CORE" ] || return 0
  local d b
  for d in "$CORE"/*/; do
    b=$(basename "$d")
    case "$b" in _*) continue ;; esac
    [ -f "$d/machine.yml" ] && printf '%s\n' "$b"
  done | sort
}

# The lab-net IP a domain currently holds, via its NIC MAC and the net's leases.
lease_ip() {
  local dom="$1" net mac
  net=$(lab '.network.name')
  mac=$(virsh -q domiflist "$dom" 2>/dev/null | awk -v n="$net" '$3 == n {print $5}' | head -1)
  [ -n "$mac" ] || return 0
  virsh -q net-dhcp-leases "$net" 2>/dev/null | awk -v m="$mac" 'index($0, m) {print $5}' | cut -d/ -f1 | head -1
}
