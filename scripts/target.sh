#!/usr/bin/env bash
# Target spinner. Deploys vulnerable boxes onto the isolated sakaar-lab network
# from two sources: a curated catalog (catalog/*.yml, known-good with overrides)
# and the full VulnHub index (catalog/vulnhub-index.tsv, ~hundreds of boxes).
# Download -> extract -> qemu-img convert -> virt-install --import (e1000 NIC,
# auto-detected disk bus) -> snapshot.
# shellcheck source-path=SCRIPTDIR source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

NET=$(lab '.network.name')
INDEX="$CATALOG/vulnhub-index.tsv"

# --- box sources ------------------------------------------------------------
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

index_url() { [ -f "$INDEX" ] && awk -F'\t' -v i="$1" '$1 == i {print $3; exit}' "$INDEX"; }
is_index() { [ -n "$(index_url "$1")" ]; }
idx_count() { if [ -f "$INDEX" ]; then wc -l <"$INDEX"; else echo 0; fi; }

is_curated() { [ -f "$(cat_file "$1")" ]; }

box_name() {
  if is_curated "$1"; then
    cat_get "$1" .name
  elif is_index "$1"; then
    awk -F'\t' -v i="$1" '$1 == i {print $2; exit}' "$INDEX"
  else
    printf '%s' "$1"
  fi
}

require_box() {
  [ -n "${1:-}" ] || die "a box is required. Run 'task targets' to list them."
  is_curated "$1" || is_index "$1" || die "unknown box '$1'. Run 'task targets' to list them."
}

# Deployed target VMs, by id (excludes the attacker).
deployed_ids() {
  virsh -q list --all --name 2>/dev/null | sed -n 's/^sakaar-tgt-//p' | sort
}

# Catalog value with a lab.yml default fallback.
field() {
  local v
  v=$(cat_get "$1" "$2")
  if [ -n "$v" ]; then printf '%s' "$v"; else lab "$3"; fi
}

# The lab-net IP a deployed box currently holds (via its NIC MAC).
lease_ip() {
  local dom="$1" mac
  mac=$(virsh -q domiflist "$dom" 2>/dev/null | awk -v n="$NET" '$3 == n {print $5}' | head -1)
  [ -n "$mac" ] || return 0
  virsh -q net-dhcp-leases "$NET" 2>/dev/null | awk -v m="$mac" 'index($0, m) {print $5}' | cut -d/ -f1 | head -1
}

# --- picker -----------------------------------------------------------------
BOX=""
choose() {
  local scope="$1" arg="${2:-}" sel id
  if [ -n "$arg" ]; then
    require_box "$arg"
    BOX="$arg"
    return
  fi
  command -v fzf >/dev/null 2>&1 || die "specify a box (BOX=<id>); run 'task targets' to list."
  if [ "$scope" = deployed ]; then
    local ids
    ids=$(deployed_ids)
    [ -n "$ids" ] || die "no deployed boxes. Run 'task deploy' first."
    sel=$(
      for id in $ids; do
        printf '%s\t%s\t%s\n' "$id" "$(box_name "$id")" "$(domain_state "$(dom_of "$id")")"
      done | column -t -s $'\t' | fzf --prompt='deployed box> ' --height=45% --reverse --header='pick a deployed box'
    ) || true
  else
    sel=$(
      {
        for id in $(cat_ids); do
          printf '%s\t[curated] %s (%s)\n' "$id" "$(cat_get "$id" .name)" "$(cat_get "$id" .difficulty)"
        done
        [ -f "$INDEX" ] && awk -F'\t' '{printf "%s\t%s\n", $1, $2}' "$INDEX"
      } | column -t -s $'\t' | fzf --prompt='deploy box> ' --height=60% --reverse \
        --header="pick a box - $(idx_count) VulnHub boxes + curated"
    ) || true
  fi
  [ -n "$sel" ] || exit 0
  BOX=$(awk '{print $1}' <<<"$sel")
}

# --- listings ---------------------------------------------------------------
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
  local n
  n=$(idx_count)
  [ "$n" -gt 0 ] && printf '\n+ %s VulnHub boxes available - run %stask deploy%s to search them\n' "$n" "$C" "$Z"
}

cmd_status() {
  printf '%sattacker:%s\n' "$B" "$Z"
  virsh list --all | grep -E "Name|sakaar-kali|--" || true
  printf '\n%sdeployed targets:%s\n' "$B" "$Z"
  local ids
  ids=$(deployed_ids)
  if [ -z "$ids" ]; then
    printf '  (none - run %stask deploy%s)\n' "$C" "$Z"
    return
  fi
  {
    printf 'BOX\tNAME\tSTATE\tIP\n'
    local id dom ip
    for id in $ids; do
      dom=$(dom_of "$id")
      ip=$(lease_ip "$dom")
      [ -n "$ip" ] || ip='-'
      printf '%s\t%s\t%s\t%s\n' "$id" "$(box_name "$id")" "$(domain_state "$dom")" "$ip"
    done
  } | column -t -s $'\t'
}

# --- deploy -----------------------------------------------------------------
deploy() {
  local id="$1"
  require_box "$id"
  local dom
  dom=$(dom_of "$id")
  domain_exists "$dom" && {
    msg "$id already deployed as $dom (IP: $(lease_ip "$dom" || echo pending))"
    return 0
  }

  local url fmt sha mem cpus disk_bus nic fixup
  if is_curated "$id"; then
    url=$(cat_get "$id" .url)
    fmt=$(cat_get "$id" .format)
    sha=$(cat_get "$id" .sha256)
    mem=$(field "$id" .memory .target_defaults.memory)
    cpus=$(field "$id" .cpus .target_defaults.cpus)
    disk_bus=$(field "$id" .disk_bus .target_defaults.disk_bus)
    nic=$(field "$id" .nic_model .target_defaults.nic_model)
    fixup=$(cat_get "$id" .fixup)
  else
    url=$(index_url "$id")
    fmt=ova
    sha=''
    mem=$(lab .target_defaults.memory)
    cpus=$(lab .target_defaults.cpus)
    disk_bus=auto
    nic=$(lab .target_defaults.nic_model)
    fixup=''
  fi

  local work arc
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
    7z)
      step "extracting 7z"
      (cd "$work" && 7z x -y "$(basename "$arc")" >/dev/null)
      ;;
    qcow2) : ;;
    *) die "unknown format '$fmt' for $id" ;;
  esac

  # Auto-detect the disk bus from the OVF (IDE on old boxes, else SATA).
  if [ "$disk_bus" = auto ]; then
    local ovf
    ovf=$(find "$work" -maxdepth 3 -iname '*.ovf' | head -1)
    if [ -n "$ovf" ] && grep -qiE 'IDE Controller|ideController|ResourceType>5<' "$ovf"; then
      disk_bus=ide
    else
      disk_bus=sata
    fi
    step "auto-detected disk bus: $disk_bus"
  fi

  local qcow src
  qcow="$work/box.qcow2"
  if [ ! -f "$qcow" ]; then
    src=$(find "$work" -maxdepth 3 -type f \( -iname '*.vmdk' -o -iname '*.vdi' -o -iname '*.qcow2' -o -iname '*.img' \) | head -1)
    [ -n "$src" ] || die "no disk image found under $work"
    if [ "${src##*.}" = qcow2 ]; then
      cp "$src" "$qcow"
    else
      step "converting disk to qcow2"
      qemu-img convert -O qcow2 "$src" "$qcow"
    fi
  fi

  [ -z "$fixup" ] || {
    step "applying fixup"
    eval "virt-customize -a \"$qcow\" $fixup" || msg "fixup warning (continuing)"
  }

  step "importing $dom on $NET (disk=$disk_bus, nic=$nic)"
  virt-install --name "$dom" \
    --memory "$mem" --vcpus "$cpus" \
    --import --disk path="$qcow",format=qcow2,bus="$disk_bus" \
    --osinfo detect=on,require=off \
    --network network="$NET",model="$nic" \
    --graphics spice --video qxl --noautoconsole

  virsh snapshot-create-as "$dom" clean 'clean baseline' >/dev/null 2>&1 || true
  msg "${G}deployed${Z} $id as $dom. Find its IP with ${C}task status${Z}, then attack it from Kali."
}

# --- dispatch ---------------------------------------------------------------
case "${1:-list}" in
  list) cmd_list ;;
  status) cmd_status ;;
  deploy)
    choose catalog "${2:-}"
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
  *) die "usage: target.sh {list|status|deploy|start|stop|reset|destroy|console|ip} [box]" ;;
esac
