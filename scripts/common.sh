#!/usr/bin/env bash
# Shared helpers for the Sakaar scripts. Source this; do not execute.
# shellcheck disable=SC2034  # many definitions here are consumed by sourcing scripts
set -euo pipefail

ROOT=${SAKAAR_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
LAB="$ROOT/config/lab.yml"
VMS="$ROOT/vms"
CATALOG="$ROOT/catalog"

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
