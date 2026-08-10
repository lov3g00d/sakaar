#!/usr/bin/env bash
# The isolated DHCP lab network (sakaar-lab). Targets get an IP here but have no
# route to the outside; the attacker is dual-homed onto it.
# shellcheck source-path=SCRIPTDIR source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

net=$(lab '.network.name')

define_xml() {
  cat <<EOF
<network>
  <name>${net}</name>
  <bridge name='$(lab .network.bridge)'/>
  <ip address='$(lab .network.gateway)' netmask='$(lab .network.netmask)'>
    <dhcp>
      <range start='$(lab .network.dhcp_start)' end='$(lab .network.dhcp_end)'/>
    </dhcp>
  </ip>
</network>
EOF
}

case "${1:-status}" in
  up)
    if ! virsh net-info "$net" >/dev/null 2>&1; then
      tmp=$(mktemp)
      define_xml >"$tmp"
      virsh net-define "$tmp" >/dev/null
      rm -f "$tmp"
    fi
    virsh net-start "$net" >/dev/null 2>&1 || true
    virsh net-autostart "$net" >/dev/null 2>&1 || true
    msg "network ${B}${net}${Z} up  ($(lab .network.gateway)/24, DHCP $(lab .network.dhcp_start)-$(lab .network.dhcp_end), isolated)"
    ;;
  down)
    virsh net-destroy "$net" 2>/dev/null || true
    ;;
  status)
    virsh net-list --all
    ;;
  *)
    die "usage: lab.sh {up|down|status}"
    ;;
esac
