#!/bin/bash
# Compute the host-side UID or GID that a given container-side ID maps to,
# for an unprivileged Proxmox LXC — using the container's actual lxc.idmap
# lines when present, falling back to Proxmox's default unprivileged mapping
# (0-65535 -> 100000-165535) when they're absent.
#
# Usage: map_container_id.sh <vmid> <u|g> <container_id>
# Run on the Proxmox host (needs read access to /etc/pve/lxc/<vmid>.conf).

set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: $0 <vmid> <u|g> <container_id>" >&2
  exit 1
fi

vmid="$1"
kind="$2"
cid="$3"

if [ "$kind" != "u" ] && [ "$kind" != "g" ]; then
  echo "kind must be 'u' or 'g', got: $kind" >&2
  exit 1
fi

conf="/etc/pve/lxc/${vmid}.conf"
[ -f "$conf" ] || { echo "no such container conf: $conf" >&2; exit 1; }

lines=$(grep -E "^lxc\.idmap: ${kind} " "$conf" || true)

if [ -z "$lines" ]; then
  # No custom mapping for this type -> PVE's default unprivileged mapping.
  lines="lxc.idmap: ${kind} 0 100000 65536"
fi

while IFS= read -r line; do
  # line looks like: lxc.idmap: u 0 100000 65536
  read -r _ _ cstart hstart range <<< "$line"
  if [ "$cid" -ge "$cstart" ] && [ "$cid" -lt "$((cstart + range))" ]; then
    echo "$((hstart + cid - cstart))"
    exit 0
  fi
done <<< "$lines"

echo "no idmap range on container ${vmid} covers ${kind}id ${cid}" >&2
exit 1
