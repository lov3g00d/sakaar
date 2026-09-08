#!/usr/bin/env bash
# The repeatable range core: persistent infrastructure (bastions) that `task up`
# stands up on the isolated lab net and keeps live, distinct from the rotating
# challenge machines under machines/. Recipes live under core/; they are built
# by the same engine as challenge machines but without flags.
# shellcheck source-path=SCRIPTDIR source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

NET=$(lab '.network.name')
HERE="$(dirname "${BASH_SOURCE[0]}")"

core_dom() { echo "sakaar-core-$1"; }

deploy_one() {
  local id="$1" dom out
  dom=$(core_dom "$id")
  domain_exists "$dom" && return 0
  out="$VMS/$id/box.qcow2"
  [ -f "$out" ] || bash "$HERE/build.sh" "$id"
  step "deploying core $id as $dom on $NET"
  virt-install --name "$dom" \
    --memory "$(core_get "$id" .memory)" --vcpus "$(core_get "$id" .cpus)" \
    --import --disk path="$out",format=qcow2,bus=virtio \
    --osinfo detect=on,require=off \
    --network network="$NET",model=virtio \
    --graphics spice --video qxl --noautoconsole
  virsh snapshot-create-as "$dom" clean 'clean baseline' >/dev/null 2>&1 || true
}

up() {
  local ids id
  ids=$(core_ids)
  [ -n "$ids" ] || {
    msg "no core machines defined (core/ is empty)"
    return 0
  }
  for id in $ids; do
    deploy_one "$id"
    [ "$(domain_state "$(core_dom "$id")")" = running ] || virsh start "$(core_dom "$id")" >/dev/null 2>&1 || true
  done
  msg "${G}core up${Z}. Find the portal IP with ${C}task status${Z}"
}

each() {
  local action="$1" id dom
  for id in $(core_ids); do
    dom=$(core_dom "$id")
    domain_exists "$dom" || continue
    case "$action" in
      down) virsh shutdown "$dom" 2>/dev/null || true ;;
      reset)
        if virsh snapshot-revert "$dom" clean 2>/dev/null; then
          msg "reverted core $id"
        else
          msg "skipped $id (no clean snapshot)"
        fi
        ;;
      destroy)
        virsh destroy "$dom" 2>/dev/null || true
        virsh undefine "$dom" --snapshots-metadata --remove-all-storage 2>/dev/null ||
          virsh undefine "$dom" 2>/dev/null || true
        msg "destroyed core $id"
        ;;
    esac
  done
}

case "${1:-up}" in
  up) up ;;
  down) each down ;;
  reset) each reset ;;
  destroy) each destroy ;;
  rebuild)
    require="${2:-}"
    for id in $(core_ids); do
      [ -n "$require" ] && [ "$require" != "$id" ] && continue
      rm -f "$VMS/$id/box.qcow2"
      bash "$HERE/build.sh" "$id"
    done
    ;;
  *) die "usage: core.sh {up|down|reset|destroy|rebuild [id]}" ;;
esac
