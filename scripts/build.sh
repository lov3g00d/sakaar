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
  local dir base out prov seed dom ud
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
  # Match the NIC by name glob, not MAC. Cloud images otherwise pin netplan to
  # the build-time MAC, so the deployed box (different MAC) never gets a lease.
  printf 'version: 2\nethernets:\n  lab:\n    match:\n      name: "e*"\n    dhcp4: true\n' >"$VMS/$id/network-config"
  ud="$VMS/$id/user-data"
  inject_flags "$id" "$prov" "$ud"
  cloud-localds --network-config "$VMS/$id/network-config" "$seed" "$ud" "$VMS/$id/meta-data"

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
  rm -f "$seed" "$VMS/$id/meta-data" "$VMS/$id/network-config" "$ud"
  msg "${G}built${Z} $id -> ${out#"$ROOT"/}. Deploy with ${C}task deploy BOX=$id${Z}"
}

# The engine owns flags: opaque, unique per build, injected into the recipe's
# write_files so recipes never hardcode them. root.txt is root-only. user.txt
# goes to the foothold user's home with defer:true - written in the final
# stage, after cloud-init has created that user and its home dir. Plaintext
# lands in vms/<id>/flags.txt (gitignored) for checking submissions.
inject_flags() {
  local id="$1" src="$2" dst="$3" fu uflag rflag
  fu=$(mach_get "$id" .foothold_user)
  # head-then-od (not tr|head): under `set -o pipefail`, tr piped into an
  # early-closing head takes SIGPIPE and aborts the build.
  uflag="SAKAAR{$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')}"
  rflag="SAKAAR{$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')}"
  cp -f "$src" "$dst"
  RF="$rflag" yq -i '.write_files += [{"path": "/root/root.txt", "content": strenv(RF) + "\n", "permissions": "0600"}]' "$dst"
  if [ -n "$fu" ] && [ "$fu" != "null" ]; then
    UF="$uflag" FU="$fu" yq -i '.write_files += [{"path": "/home/" + strenv(FU) + "/user.txt", "content": strenv(UF) + "\n", "permissions": "0644", "defer": true}]' "$dst"
  fi
  printf 'user.txt: %s\nroot.txt: %s\n' "$uflag" "$rflag" >"$VMS/$id/flags.txt"
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
