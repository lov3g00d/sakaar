#!/usr/bin/env bash
# Build an authored vulnerable machine deterministically: base cloud image +
# cloud-init provisioning (recipe), booted once on the NAT network and powered
# off when done -> a ready-to-deploy qcow2. No AI, no external box mirror.
# shellcheck source-path=SCRIPTDIR source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ensure_base() {
  local key="$1" url dest
  url=$(yqf "$LAB" ".bases.\"$key\".url")
  [ -n "$url" ] || die "unknown base image '$key' (see config/lab.yml)"
  mkdir -p "$VMS/base"
  dest="$VMS/base/$key.qcow2"
  download "$url" "$dest" >&2
  printf '%s' "$dest"
}

build() {
  local id="$1"
  is_machine "$id" || die "no machine '$id' (expected machines/$id/machine.yml)"
  local dir base out prov seed dom
  dir=$(mach_dir "$id")
  prov="$dir/provision.yml"
  [ -f "$prov" ] || die "no provision.yml for $id"

  base=$(ensure_base "$(mach_get "$id" .base)")
  mkdir -p "$VMS/$id"
  out="$VMS/$id/box.qcow2"
  step "copying base image"
  cp -f "$base" "$out"

  step "building cloud-init seed"
  seed="$VMS/$id/seed.iso"
  printf 'instance-id: sakaar-%s\nlocal-hostname: %s\n' "$id" "$id" >"$VMS/$id/meta-data"
  cloud-localds "$seed" "$prov" "$VMS/$id/meta-data"

  dom="sakaar-build-$id"
  virsh destroy "$dom" 2>/dev/null || true
  virsh undefine "$dom" 2>/dev/null || true

  step "provisioning $id (boot + cloud-init; powers off when finished)"
  virt-install --name "$dom" \
    --memory "$(mach_get "$id" .memory)" --vcpus "$(mach_get "$id" .cpus)" \
    --import \
    --disk path="$out",format=qcow2,bus=virtio \
    --disk path="$seed",device=cdrom \
    --osinfo detect=on,require=off \
    --network network=default,model=virtio \
    --graphics none --noautoconsole

  step "waiting for provisioning to complete"
  for _ in $(seq 1 120); do
    [ "$(domain_state "$dom")" = "shut off" ] && break
    sleep 10
  done
  if [ "$(domain_state "$dom")" != "shut off" ]; then
    virsh destroy "$dom" 2>/dev/null || true
    virsh undefine "$dom" 2>/dev/null || true
    die "build timed out - cloud-init did not power the VM off"
  fi

  virsh undefine "$dom" 2>/dev/null || true
  rm -f "$seed" "$VMS/$id/meta-data"
  msg "${G}built${Z} $id -> ${out#"$ROOT"/}. Deploy with ${C}task deploy BOX=$id${Z}"
}

case "${1:-}" in
  list) mach_ids ;;
  "")
    command -v fzf >/dev/null 2>&1 || die "specify a machine: task build MACHINE=<id> (see 'task machines')"
    m=$(mach_ids | fzf --prompt='build machine> ' --height=40% --reverse) || exit 0
    [ -n "$m" ] && build "$m"
    ;;
  *) build "$1" ;;
esac
