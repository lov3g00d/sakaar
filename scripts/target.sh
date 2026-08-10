#!/usr/bin/env bash
# VulnHub target spinner: deploy vulnerable boxes from the catalog onto the
# isolated sakaar-lab network. Download -> extract -> qemu-img convert ->
# virt-install --import (e1000 NIC for legacy compatibility) -> snapshot.
# shellcheck source-path=SCRIPTDIR source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

NET=$(lab '.network.name')

cat_file() { echo "$CATALOG/$1.yml"; }
cat_get() { yqf "$(cat_file "$1")" "$2"; }
dom_of() { echo "sakaar-tgt-$1"; }

cat_ids() {
  [ -d "$CATALOG" ] || return 0
  local f
  for f in "$CATALOG"/*.yml; do
    [ -e "$f" ] || continue
    basename "$f" .yml
  done | sort
}

require_box() {
  [ -n "${1:-}" ] || die "a box is required. Run 'task targets' to list them."
  [ -f "$(cat_file "$1")" ] || die "unknown box '$1'. Run 'task targets' to list them."
}

# Catalog value, falling back to the lab.yml default.
field() {
  local v
  v=$(cat_get "$1" "$2")
  if [ -n "$v" ]; then printf '%s' "$v"; else lab "$3"; fi
}

# The lab-net IP a deployed box currently holds (via its NIC MAC).
lease_ip() {
  local dom="$1" mac
  mac=$(virsh -q domiflist "$dom" 2>/dev/null | awk -v n="$NET" '$3==n{print $5}' | head -1)
  [ -n "$mac" ] || return 0
  virsh -q net-dhcp-leases "$NET" 2>/dev/null | awk -v m="$mac" 'index($0,m){print $5}' | cut -d/ -f1 | head -1
}

cmd_list() {
  {
    printf 'BOX\tNAME\tDIFFICULTY\tSTATE\tIP\n'
    local id dom st ip
    for id in $(cat_ids); do
      dom=$(dom_of "$id")
      if domain_exists "$dom"; then st=$(domain_state "$dom"); else st='-'; fi
      ip=$(lease_ip "$dom")
      [ -n "$ip" ] || ip='-'
      printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$(cat_get "$id" .name)" "$(cat_get "$id" .difficulty)" "$st" "$ip"
    done
  } | column -t -s $'\t'
}

cmd_status() {
  printf '%sattacker:%s\n' "$B" "$Z"
  virsh list --all | grep -E "Name|sakaar-kali|--" || true
  printf '\n%stargets:%s\n' "$B" "$Z"
  cmd_list
}

deploy() {
  local id="${1:-}"
  if [ -z "$id" ]; then
    command -v fzf >/dev/null 2>&1 || die "no box given. Usage: task deploy BOX=<id>"
    id=$(cat_ids | fzf --prompt='deploy box> ' --height=40% --reverse) || return 0
  fi
  require_box "$id"
  local dom
  dom=$(dom_of "$id")
  domain_exists "$dom" && {
    msg "$id already deployed as $dom (IP: $(lease_ip "$dom" || echo pending))"
    return 0
  }

  local url fmt sha work arc src qcow fixup
  url=$(cat_get "$id" .url)
  fmt=$(cat_get "$id" .format)
  sha=$(cat_get "$id" .sha256)
  work="$VMS/$id"
  mkdir -p "$work"
  arc="$work/$(basename "$url")"

  [ -f "$arc" ] || {
    step "downloading $id"
    curl -L --fail -C - -o "$arc" "$url"
  }
  [ -z "$sha" ] || {
    step "verifying checksum"
    echo "${sha}  ${arc}" | sha256sum -c - >/dev/null || die "checksum mismatch"
  }

  case "$fmt" in
    ova)
      step "extracting OVA"
      tar -xf "$arc" -C "$work"
      ;;
    zip)
      step "extracting ZIP"
      (cd "$work" && unzip -oq "$(basename "$arc")")
      ;;
    qcow2) : ;;
    *) die "unknown format '$fmt' for $id" ;;
  esac

  qcow="$work/$id.qcow2"
  if [ ! -f "$qcow" ]; then
    src=$(find "$work" -maxdepth 2 -type f \( -iname '*.vmdk' -o -iname '*.vdi' -o -iname '*.qcow2' -o -iname '*.img' \) | head -1)
    [ -n "$src" ] || die "no disk image found under $work"
    if [ "${src##*.}" = qcow2 ]; then
      cp "$src" "$qcow"
    else
      step "converting disk to qcow2"
      qemu-img convert -O qcow2 "$src" "$qcow"
    fi
  fi

  # Optional per-box fixup for pinned NIC configs (rarely needed).
  fixup=$(cat_get "$id" .fixup)
  [ -z "$fixup" ] || {
    step "applying fixup"
    eval "virt-customize -a \"$qcow\" $fixup" || msg "fixup warning (continuing)"
  }

  step "importing $dom on $NET"
  virt-install --name "$dom" \
    --memory "$(field "$id" .memory .target_defaults.memory)" \
    --vcpus "$(field "$id" .cpus .target_defaults.cpus)" \
    --import --disk path="$qcow",format=qcow2,bus="$(field "$id" .disk_bus .target_defaults.disk_bus)" \
    --osinfo detect=on,require=off \
    --network network="$NET",model="$(field "$id" .nic_model .target_defaults.nic_model)" \
    --graphics spice --video qxl --noautoconsole

  virsh snapshot-create-as "$dom" clean 'clean baseline' >/dev/null 2>&1 || true
  msg "${G}deployed${Z} $id as $dom. Find its IP with ${C}task status${Z}, then attack it from Kali."
}

case "${1:-list}" in
  list) cmd_list ;;
  status) cmd_status ;;
  deploy) deploy "${2:-}" ;;
  start)
    require_box "${2:-}"
    virsh start "$(dom_of "$2")"
    ;;
  stop)
    require_box "${2:-}"
    virsh shutdown "$(dom_of "$2")"
    ;;
  reset)
    require_box "${2:-}"
    virsh snapshot-revert "$(dom_of "$2")" clean && msg "reverted $2 to its clean baseline"
    ;;
  destroy)
    require_box "${2:-}"
    virsh destroy "$(dom_of "$2")" 2>/dev/null || true
    virsh undefine "$(dom_of "$2")" --snapshots-metadata --remove-all-storage 2>/dev/null ||
      virsh undefine "$(dom_of "$2")" 2>/dev/null || true
    msg "destroyed $2"
    ;;
  console)
    require_box "${2:-}"
    virt-viewer "$(dom_of "$2")" >/dev/null 2>&1 &
    ;;
  ip)
    require_box "${2:-}"
    lease_ip "$(dom_of "$2")"
    ;;
  *) die "usage: target.sh {list|status|deploy|start|stop|reset|destroy|console|ip} [box]" ;;
esac
