#!/usr/bin/env bash
# Read-only host preflight for the libvirt-native range. Never mutates the host.
# [SETUP] = a host prerequisite you enable; [ERROR] = something that breaks the
# framework itself. Only ERRORs make this exit non-zero.
set -uo pipefail

ROOT=${SAKAAR_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
export LIBVIRT_DEFAULT_URI="qemu:///system"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' C=$'\e[36m' Z=$'\e[0m'
else
  G='' Y='' R='' C='' Z=''
fi

errors=0 warns=0 setups=0
ok() { printf '%s[OK]%s    %-16s %s\n' "$G" "$Z" "$1" "${2:-}"; }
warn() {
  printf '%s[WARN]%s  %-16s %s\n' "$Y" "$Z" "$1" "${2:-}"
  warns=$((warns + 1))
}
err() {
  printf '%s[ERROR]%s %-16s %s\n' "$R" "$Z" "$1" "${2:-}"
  errors=$((errors + 1))
}
setup() {
  printf '%s[SETUP]%s %-16s %s\n' "$C" "$Z" "$1" "${2:-}"
  setups=$((setups + 1))
}
have() { command -v "$1" >/dev/null 2>&1; }
tool() { if have "$1"; then ok "$1" "present"; else err "$1" "missing - run inside 'nix develop'"; fi; }

echo "== environment =="
ok os "$(uname -s) $(uname -r)"
ok arch "$(uname -m)"

echo
echo "== flake-provided tooling =="
for t in task virsh virt-install virt-viewer qemu-img 7z yq jq fzf curl; do tool "$t"; done

echo
echo "== host virtualisation =="
if grep -Eq '(^| )(vmx|svm)( |$)' /proc/cpuinfo 2>/dev/null; then ok cpu-virt "VT-x/AMD-V present"; else setup cpu-virt "enable virtualisation in BIOS/UEFI"; fi
if [ -e /dev/kvm ]; then ok /dev/kvm "present"; else setup /dev/kvm "KVM unavailable"; fi
if virsh version >/dev/null 2>&1; then ok libvirtd "reachable"; else setup libvirtd "enable virtualisation.libvirtd (see docs/nix.md)"; fi

echo
echo "== range state =="
if virsh net-info sakaar-lab >/dev/null 2>&1 && virsh net-info sakaar-lab 2>/dev/null | grep -q 'Active:.*yes'; then
  ok sakaar-lab "network active"
else
  setup sakaar-lab "run 'task up' to create the lab network"
fi
kali=$(virsh domstate sakaar-kali 2>/dev/null || echo "not deployed")
ok attacker "kali: ${kali}"
m=$(find "$ROOT/machines" -mindepth 1 -maxdepth 1 -type d ! -name '_*' 2>/dev/null | wc -l)
c=$(find "$ROOT/core" -mindepth 1 -maxdepth 1 -type d ! -name '_*' 2>/dev/null | wc -l)
ok machines "${m} authored, ${c} core"

echo
echo "== resources =="
mem=$(awk '/MemTotal/{printf "%.1f", $2/1048576}' /proc/meminfo 2>/dev/null)
[ -z "$mem" ] || { if awk "BEGIN{exit !($mem>=8)}"; then ok memory "${mem} GiB"; else warn memory "${mem} GiB (8+ recommended)"; fi; }
disk=$(df -PBG "$ROOT" 2>/dev/null | awk 'NR==2{gsub("G","",$4);print $4}')
[ -z "$disk" ] || { if [ "$disk" -ge 40 ]; then ok disk "${disk} GiB free"; else warn disk "${disk} GiB free (40+ recommended)"; fi; }

echo
printf 'summary: %s error(s), %s warning(s), %s setup step(s)\n' "$errors" "$warns" "$setups"
[ "$setups" -eq 0 ] || echo "note: [SETUP] items are host prerequisites; enable them and re-run."
[ "$errors" -eq 0 ]
