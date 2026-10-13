#!/usr/bin/env bash
# Create (or confirm) a simulation container on a Proxmox host.
#   hosts/make-ct.sh <pve-host> <vmid> <hostname> <bridge> <ip/cidr> <gw|-> <cores> <mem_mb>
#                    [--nic2 <bridge>,<ip/cidr>] [--nameserver <ip>] [--disk <GB>] [--task <N>]
# Unprivileged Ubuntu 24.04, nesting+keyctl, TUN passthrough, tag hs-sim, onboot.
# Ledgers "pct destroy" before creating. Re-running on an existing hs-sim CT just ensures it runs;
# a VMID that exists without the hs-sim tag is never touched.
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
[ $# -ge 8 ] || die "usage: $0 <pve-host> <vmid> <hostname> <bridge> <ip/cidr> <gw|-> <cores> <mem_mb> [opts]"
host=$1 vmid=$2 name=$3 bridge=$4 ip=$5 gw=$6 cores=$7 mem=$8; shift 8
nic2= ns=$IP_CAMPUS disk=8 task=${SIM_TASK:-?}
while [ $# -gt 0 ]; do
  case $1 in
    --nic2) nic2=$2 ;; --nameserver) ns=$2 ;; --disk) disk=$2 ;; --task) task=$2 ;;
    *) die "unknown option $1" ;;
  esac; shift 2
done

if run_on "$host" "pct status $vmid" >/dev/null 2>&1; then
  run_on "$host" "pct config $vmid" | grep -q '^tags:.*hs-sim' || die "VMID $vmid exists on $host and is not an hs-sim CT"
  log "CT $vmid ($name) exists; ensuring it is running"
  run_on "$host" "pct status $vmid | grep -q running || pct start $vmid"
  exit 0
fi

ledger_add "$task" "$host" ct "$vmid" "pct status $vmid >/dev/null 2>&1 || exit 0; pct stop $vmid >/dev/null 2>&1; pct destroy $vmid --purge"
net0="name=eth0,bridge=$bridge,ip=$ip"; [ "$gw" != - ] && net0+=",gw=$gw"
args="--hostname $name --cores $cores --memory $mem --swap 512 --rootfs local-lvm:$disk"
args+=" --net0 $net0 --nameserver $ns --searchdomain $UNI_DOMAIN --unprivileged 1"
args+=" --features nesting=1,keyctl=1 --tags hs-sim --onboot 1"
[ -n "$nic2" ] && args+=" --net1 name=eth1,bridge=${nic2%%,*},ip=${nic2#*,}"
log "creating CT $vmid ($name) on $host"
run_on "$host" "pct create $vmid $TEMPLATE $args >/dev/null"
run_on "$host" "printf '%s\n' 'lxc.cgroup2.devices.allow: c 10:200 rwm' 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file' >> /etc/pve/lxc/$vmid.conf"
run_on "$host" "pct start $vmid"
for _ in $(seq 30); do
  ct_exec "$host" "$vmid" "getent hosts archive.ubuntu.com >/dev/null" 2>/dev/null && { log "CT $vmid up"; exit 0; }
  sleep 2
done
die "CT $vmid started but has no working DNS/network after 60s"
