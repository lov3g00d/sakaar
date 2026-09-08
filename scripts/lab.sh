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
  <domain name='$(lab .network.domain)' localOnly='yes'/>
  <ip address='$(lab .network.gateway)' netmask='$(lab .network.netmask)'>
    <dhcp>
      <range start='$(lab .network.dhcp_start)' end='$(lab .network.dhcp_end)'/>
    </dhcp>
  </ip>
</network>
EOF
}

define_net() {
  local tmp
  tmp=$(mktemp)
  define_xml >"$tmp"
  virsh net-define "$tmp" >/dev/null
  rm -f "$tmp"
}

case "${1:-status}" in
  up)
    domain=$(lab .network.domain)
    if virsh net-info "$net" >/dev/null 2>&1; then
      # Reconcile a definition made before a config change (e.g. one created
      # before the DNS domain was added). Applying it needs a recreate, which
      # detaches any attached VMs, so flag that they must restart.
      if [ -n "$domain" ] && ! virsh net-dumpxml --inactive "$net" 2>/dev/null | grep -q "domain name='$domain'"; then
        step "updating lab network definition (adds DNS domain $domain)"
        virsh net-destroy "$net" >/dev/null 2>&1 || true
        virsh net-undefine "$net" >/dev/null 2>&1 || true
        define_net
        msg "note: restart attached VMs so they reattach to the recreated network"
      fi
    else
      define_net
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
