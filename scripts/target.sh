#!/usr/bin/env bash
# Target lifecycle: deploy authored machines onto the isolated sakaar-lab
# network and manage them. Build a machine with `task build` first.
# shellcheck source-path=SCRIPTDIR source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

NET=$(lab '.network.name')

dom_of() { echo "sakaar-tgt-$1"; }
built_qcow() { echo "$VMS/$1/box.qcow2"; }
is_built() { [ -f "$(built_qcow "$1")" ]; }

require_box() {
  [ -n "${1:-}" ] || die "a machine is required. Run 'task machines' to list them."
  is_machine "$1" || die "unknown machine '$1'. Run 'task machines' to list them."
}

# Deployed target VMs, by id (excludes the attacker).
deployed_ids() {
  virsh -q list --all --name 2>/dev/null | sed -n 's/^sakaar-tgt-//p' | sort
}

# The lab-net IP a deployed machine currently holds (via its NIC MAC).
lease_ip() {
  local dom="$1" mac
  mac=$(virsh -q domiflist "$dom" 2>/dev/null | awk -v n="$NET" '$3 == n {print $5}' | head -1)
  [ -n "$mac" ] || return 0
  virsh -q net-dhcp-leases "$NET" 2>/dev/null | awk -v m="$mac" 'index($0, m) {print $5}' | cut -d/ -f1 | head -1
}

BOX=""
choose() {
  local scope="$1" arg="${2:-}" ids sel id
  if [ -n "$arg" ]; then
    require_box "$arg"
    BOX="$arg"
    return
  fi
  command -v fzf >/dev/null 2>&1 || die "specify a machine (BOX=<id>); run 'task machines' to list."
  if [ "$scope" = deployed ]; then ids=$(deployed_ids); else ids=$(mach_ids); fi
  [ -n "$ids" ] || die "no ${scope} machines available."
  sel=$(
    for id in $ids; do
      printf '%s\t%s\t%s\n' "$id" "$(mach_get "$id" .name)" "$(mach_get "$id" .difficulty)"
    done | column -t -s $'\t' | fzf --prompt="${scope} machine> " --height=45% --reverse --header='pick a machine'
  ) || true
  [ -n "$sel" ] || exit 0
  BOX=$(awk '{print $1}' <<<"$sel")
}

cmd_list() {
  {
    printf 'MACHINE\tNAME\tDIFFICULTY\tBUILT\tSTATE\tIP\n'
    local id dom st ip built
    for id in $(mach_ids); do
      dom=$(dom_of "$id")
      if is_built "$id"; then built=yes; else built=no; fi
      if domain_exists "$dom"; then st=$(domain_state "$dom"); else st='-'; fi
      ip=$(lease_ip "$dom")
      [ -n "$ip" ] || ip='-'
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$(mach_get "$id" .name)" "$(mach_get "$id" .difficulty)" "$built" "$st" "$ip"
    done
  } | column -t -s $'\t'
}

cmd_status() {
  printf '%sattacker:%s\n' "$B" "$Z"
  virsh list --all | grep -E "Name|sakaar-kali|--" || true
  printf '\n%sdeployed targets:%s\n' "$B" "$Z"
  local ids
  ids=$(deployed_ids)
  if [ -z "$ids" ]; then
    printf '  (none - %stask build%s a machine, then %stask deploy%s)\n' "$C" "$Z" "$C" "$Z"
    return
  fi
  {
    printf 'MACHINE\tNAME\tSTATE\tIP\n'
    local id dom ip
    for id in $ids; do
      dom=$(dom_of "$id")
      ip=$(lease_ip "$dom")
      [ -n "$ip" ] || ip='-'
      printf '%s\t%s\t%s\t%s\n' "$id" "$(mach_get "$id" .name)" "$(domain_state "$dom")" "$ip"
    done
  } | column -t -s $'\t'
}

deploy() {
  local id="$1"
  require_box "$id"
  local dom out
  dom=$(dom_of "$id")
  domain_exists "$dom" && {
    msg "$id already deployed as $dom (IP: $(lease_ip "$dom" || echo pending))"
    return 0
  }
  out=$(built_qcow "$id")
  [ -f "$out" ] || die "$id is not built yet - run 'task build $id' first."

  step "importing $dom on $NET"
  virt-install --name "$dom" \
    --memory "$(mach_get "$id" .memory)" --vcpus "$(mach_get "$id" .cpus)" \
    --import --disk path="$out",format=qcow2,bus=virtio \
    --osinfo detect=on,require=off \
    --network network="$NET",model=virtio \
    --graphics spice --video qxl --noautoconsole

  virsh snapshot-create-as "$dom" clean 'clean baseline' >/dev/null 2>&1 || true
  msg "${G}deployed${Z} $id as $dom. Find its IP with ${C}task status${Z}, then attack it from Kali."
}

case "${1:-list}" in
  list) cmd_list ;;
  status) cmd_status ;;
  deploy)
    choose available "${2:-}"
    deploy "$BOX"
    ;;
  start)
    choose deployed "${2:-}"
    virsh start "$(dom_of "$BOX")"
    ;;
  stop)
    choose deployed "${2:-}"
    virsh shutdown "$(dom_of "$BOX")"
    ;;
  reset)
    choose deployed "${2:-}"
    virsh snapshot-revert "$(dom_of "$BOX")" clean && msg "reverted $BOX to its clean baseline"
    ;;
  destroy)
    choose deployed "${2:-}"
    virsh destroy "$(dom_of "$BOX")" 2>/dev/null || true
    virsh undefine "$(dom_of "$BOX")" --snapshots-metadata --remove-all-storage 2>/dev/null ||
      virsh undefine "$(dom_of "$BOX")" 2>/dev/null || true
    msg "destroyed $BOX"
    ;;
  console)
    choose deployed "${2:-}"
    virt-viewer "$(dom_of "$BOX")" >/dev/null 2>&1 &
    ;;
  ip)
    require_box "${2:-}"
    lease_ip "$(dom_of "$2")"
    ;;
  *) die "usage: target.sh {list|status|deploy|start|stop|reset|destroy|console|ip} [machine]" ;;
esac
