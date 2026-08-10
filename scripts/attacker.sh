#!/usr/bin/env bash
# The graphical Kali attack box: official prebuilt qcow2 (XFCE desktop),
# dual-homed on the NAT network (updates) and sakaar-lab (attacking targets).
# shellcheck source-path=SCRIPTDIR source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

NAME=$(lab '.kali.name')
NET=$(lab '.network.name')

import_kali() {
  domain_exists "$NAME" && return 0
  local url ver sha arc img
  url=$(lab .kali.url)
  ver=$(lab .kali.version)
  sha=$(lab .kali.sha256)
  mkdir -p "$VMS"
  arc="$VMS/$(basename "$url")"
  download "$url" "$arc"
  step "verifying checksum"
  echo "${sha}  ${arc}" | sha256sum -c - >/dev/null || die "Kali checksum mismatch"
  img="$VMS/kali-linux-${ver}-qemu-amd64.qcow2"
  if [ ! -f "$img" ]; then
    step "extracting image"
    (cd "$VMS" && 7z x -y "$(basename "$arc")" >/dev/null)
  fi
  step "importing ${NAME} (graphical, dual-homed)"
  virt-install --name "$NAME" \
    --memory "$(lab .kali.memory)" --vcpus "$(lab .kali.cpus)" --cpu host-passthrough \
    --import --disk path="$img",format=qcow2,bus=virtio \
    --osinfo detect=on,require=off \
    --network network=default,model=virtio \
    --network network="$NET",model=virtio \
    --graphics spice --video qxl --noautoconsole
}

kali_ip() {
  # Prefer the lab-net address; fall back to any lease.
  virsh -q domifaddr "$NAME" --source lease 2>/dev/null |
    awk '/ipv4/{print $4}' | cut -d/ -f1 | head -1
}

case "${1:-console}" in
  up)
    import_kali
    [ "$(domain_state "$NAME")" = running ] || virsh start "$NAME" >/dev/null
    msg "attacker ${B}${NAME}${Z} is up. Open the desktop with ${C}task attacker:console${Z}"
    ;;
  console)
    domain_exists "$NAME" || die "${NAME} not deployed. Run 'task attacker:up' first."
    [ "$(domain_state "$NAME")" = running ] || virsh start "$NAME" >/dev/null
    step "opening ${NAME} desktop"
    virt-viewer "$NAME" >/dev/null 2>&1 &
    ;;
  ssh)
    ip=$(kali_ip)
    [ -n "$ip" ] || die "no IP for ${NAME} yet (is it booted?)"
    exec ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "kali@${ip}"
    ;;
  status)
    virsh list --all
    ;;
  down)
    virsh shutdown "$NAME" 2>/dev/null || true
    ;;
  *)
    die "usage: attacker.sh {up|console|ssh|status|down}"
    ;;
esac
