#!/bin/bash
# Create a new, independent host-side CIFS mount scoped to one purpose,
# with explicit uid/gid/mode so it's writable from inside an unprivileged
# LXC. Deliberately does NOT touch any container config (pct set) — that
# needs a judgment call about which mpN slot and in-container path to use,
# which this script can't safely guess.
#
# Idempotent: refuses to run if the host mountpoint is already in /etc/fstab.
# Never echoes the password anywhere.
#
# Run on the Proxmox host as root.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: setup_scoped_cifs_mount.sh
  --server <host_or_ip>       CIFS server address
  --share <share_name>        Top-level SMB share name
  --host-mount <path>         Local mountpoint to create, e.g. /mnt/pve/NAS-101-Torrents
  --uid <id>                  Host-side uid to own the mount (see map_container_id.sh)
  --gid <id>                  Host-side gid to own the mount (see map_container_id.sh)
  --username <user>           SMB username
  [--subdir </path>]          Optional subpath within the share to mount
  [--password <value>]        SMB password (prefer --password-file instead)
  [--password-file <path>]    Existing file containing a "password=..." line
                               (e.g. an existing Proxmox storage .pw file) to
                               copy the password from
  [--creds-file <path>]       Where to write credentials (default derived
                               from --host-mount under /etc/samba/creds/)
  [--file-mode <mode>]        default 0770
  [--dir-mode <mode>]         default 0770
  [--vers <smb_version>]      default 3.1.1
  [--extra-options <opts>]    default noatime,nobrl (nobrl disables CIFS
                               byte-range locking — needed by some apps,
                               e.g. torrent clients; add noserverino too
                               if you see "stale file handle" errors)
  [--automount]               use x-systemd.automount,noauto instead of
                               _netdev,nofail — defers the actual mount
                               until first access, so an unreachable NAS
                               adds zero boot delay. Prefer this if the
                               NAS is known to be flaky or slow to come up.
EOF
  exit 1
}

subdir=""
password=""
password_file=""
creds_file=""
file_mode="0770"
dir_mode="0770"
vers="3.1.1"
extra_options="noatime,nobrl"
automount=0

while [ $# -gt 0 ]; do
  case "$1" in
    --server) server="$2"; shift 2 ;;
    --share) share="$2"; shift 2 ;;
    --subdir) subdir="$2"; shift 2 ;;
    --host-mount) host_mount="$2"; shift 2 ;;
    --uid) uid="$2"; shift 2 ;;
    --gid) gid="$2"; shift 2 ;;
    --username) username="$2"; shift 2 ;;
    --password) password="$2"; shift 2 ;;
    --password-file) password_file="$2"; shift 2 ;;
    --creds-file) creds_file="$2"; shift 2 ;;
    --file-mode) file_mode="$2"; shift 2 ;;
    --dir-mode) dir_mode="$2"; shift 2 ;;
    --vers) vers="$2"; shift 2 ;;
    --extra-options) extra_options="$2"; shift 2 ;;
    --automount) automount=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

for req in server share host_mount uid gid username; do
  if [ -z "${!req:-}" ]; then
    echo "missing required --$req" >&2
    usage
  fi
done

if [ -z "$password" ] && [ -z "$password_file" ]; then
  echo "must supply either --password or --password-file" >&2
  usage
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "must run as root (need to write /etc/fstab and mount)" >&2
  exit 1
fi

if ! command -v mount.cifs >/dev/null 2>&1; then
  echo "mount.cifs not found — install cifs-utils on the host first" >&2
  exit 1
fi

if [ -z "$creds_file" ]; then
  creds_file="/etc/samba/creds/$(basename "$host_mount" | tr 'A-Z' 'a-z')"
fi

if grep -qF "$host_mount" /etc/fstab; then
  echo "ABORT: $host_mount is already in /etc/fstab — not touching it." >&2
  echo "If you need to change its options, edit /etc/fstab by hand." >&2
  exit 1
fi

mkdir -p "$(dirname "$creds_file")"
mkdir -p "$host_mount"

if [ -n "$password_file" ]; then
  pw=$(grep -oP 'password=\K.*' "$password_file")
else
  pw="$password"
fi

printf 'username=%s\npassword=%s\n' "$username" "$pw" > "$creds_file"
chmod 600 "$creds_file"
chown root:root "$creds_file"
unset pw password

if [ "$automount" -eq 1 ]; then
  timing_opts="x-systemd.automount,noauto"
else
  timing_opts="_netdev,nofail"
fi

source_path="//${server}/${share}${subdir}"
fstab_line="${source_path} ${host_mount} cifs credentials=${creds_file},uid=${uid},gid=${gid},file_mode=${file_mode},dir_mode=${dir_mode},vers=${vers},${extra_options},${timing_opts} 0 0"

echo "$fstab_line" >> /etc/fstab
systemctl daemon-reload
mount "$host_mount"

echo "--- mounted ---"
mount | grep -F "$host_mount"
echo "--- ownership ---"
ls -ld "$host_mount"
echo
echo "Host side is ready. Credentials at: $creds_file"
echo "Next step (not done by this script) — point the container at it:"
echo "  pct set <vmid> --mpN ${host_mount},mp=<in-container-path>"
echo "  pct reboot <vmid>"
