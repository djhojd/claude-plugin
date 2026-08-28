---
name: proxmox-lxc-cifs-mount
description: Give an unprivileged Proxmox LXC container write access to a CIFS/SMB (Samba/NAS) share. Use this whenever a container can read a mounted network share but writes fail as permission denied, when the mount shows up inside the container as nobody:nogroup, or when a service running inside an LXC (Jellyfin, Sonarr/Radarr/*arr apps, qBittorrent/a torrent client, any app that needs to write/delete/rename on a NAS path) needs write access to a Samba/CIFS/SMB share. Also use when setting up a brand-new CIFS mount for an unprivileged container that will need to write to it, or when the user mentions pct set mpN, bind-mounting a NAS into an LXC, or a share owned by nobody/root inside a container. Trigger even if the user doesn't say "CIFS" or "unprivileged" explicitly — "my container can't write to the NAS", "jellyfin can't save subtitles to the share", "how do I mount samba with write access in an LXC" are all this.
---

# Proxmox LXC CIFS write access

## Why this happens

An unprivileged LXC remaps container UID/GID 0–65535 to a host-side range,
by default offset +100000 (container uid 0 → host uid 100000, container uid
110 → host uid 100110, etc.) — unless the container's `.conf` has explicit
`lxc.idmap` lines carving out exceptions (common on containers with GPU
passthrough, where specific groups like `video`/`render` are mapped 1:1
instead of offset). Never assume the default offset — always check.

Separately, most consumer NAS/Samba shares don't support CIFS unix
extensions (`nounix` in the mount options), so the CIFS client can't ask the
server "who really owns this file." Instead it fabricates ownership at mount
time from fixed options: `uid=0,gid=0,file_mode=0755,dir_mode=0755` are
`mount.cifs`'s defaults when nothing else is specified. So the mount looks
like it's owned by real root, mode `755` (owner rwx, everyone else r-x).

Combine the two: when that host-side mount (owned by real host uid/gid 0)
gets bind-mounted into an unprivileged container (`mpN` in the container's
conf, or a Proxmox `cifs:` storage entry bind-mounted the same way), host
uid/gid 0 doesn't fall inside the container's mapped range at all. It shows
up as `nobody:nogroup` inside the container, and the `755` mode means only
the literal owner gets write — which nothing inside the container can ever
be, including container root. Nobody in the container can write, no matter
what user the app runs as.

This skill is specifically about **network shares** (CIFS/SMB, and NFS
behaves the same way in practice). If what you're actually bind-mounting is
a local host filesystem (a ZFS dataset, a plain directory on `local-lvm`,
etc.), the fix is much simpler and doesn't belong to this skill: ownership
there is a real stored inode attribute, so
`chown -R <mapped-uid>:<mapped-gid> /host/path` on the host just works. Only
reach for mount-option gymnastics when `chown` isn't an option because
there's no real per-file ownership to set in the first place — which is
exactly the CIFS situation.

## Things that look like a fix but aren't

Worth ruling out explicitly, since all three of these are common detours:

- **Proxmox's Datacenter → Permissions → Groups/Roles (the `Datastore.*`
  privileges).** This is Proxmox's own API/GUI access-control system — it
  governs who can manage storage *through Proxmox*, not what a Linux
  process inside a container can read or write on a mounted path. It has
  zero effect on the kernel-level permission check that's actually failing
  here. Don't spend time configuring roles/permissions to solve this.
- **`chown` on a CIFS mount.** As above — CIFS without unix extensions
  doesn't store per-file ownership at all, so there's nothing for `chown`
  to change. The mount's `uid=`/`gid=`/`file_mode=`/`dir_mode=` options are
  the only lever you have.
- **Making the container privileged "just to get CIFS to mount."** A
  privileged container means container root *is* host root — a real
  security downgrade, and unnecessary here. Proxmox's `features: mount=cifs`
  flag (Fix path B) exists specifically to grant this capability to an
  *unprivileged* container without escalating it. If you see a guide insist
  a privileged container is required for an in-container CIFS mount, that's
  either outdated or overly conservative — don't follow it.

## Diagnose first

Don't guess — confirm the actual chain before touching anything:

1. What user/group does the app run as *inside* the container?
   `pct exec <vmid> -- id <service-user>` (or `ps aux` if you don't know the
   user).
2. What does the mountpoint look like from both sides?
   `ls -ld <path>` on the host, and `pct exec <vmid> -- ls -ld <path>` inside
   the container. If it shows `nobody:nogroup` or an owner/mode that clearly
   doesn't match the service user, this is the bug.
3. How is the container's ID mapping actually configured?
   `grep -E 'unprivileged|idmap' /etc/pve/lxc/<vmid>.conf`. No `lxc.idmap`
   lines at all means the default `u 0 100000 65536` / `g 0 100000 65536`
   applies. Custom lines mean you must map explicitly — use
   `scripts/map_container_id.sh` rather than doing the arithmetic by hand,
   since partial/exception ranges (GPU groups etc.) are easy to get wrong.
4. Where does the mount actually come from?
   Check the container's `.conf` for the `mpN` line, and whether it points
   at a raw host path or a Proxmox-managed storage under
   `/mnt/pve/<storage-name>/...`. If it's Proxmox-managed, check
   `/etc/pve/storage.cfg` for that storage's `cifs:` block (server, share,
   username) and current live mount options via `mount | grep <path>`.

## Decide the blast radius before touching anything

This is the step people skip and regret. Before changing any mount option,
find out what else depends on the *current* mount:

- `grep -l '<storage-or-path-name>' /etc/pve/lxc/*.conf /etc/pve/qemu-server/*.conf`
  — are other containers/VMs bind-mounting the same storage or subpath?
- `ls -la <mount-root>` — does the share also hold things the *host itself*
  writes to (backup scripts, ISO/template storage, other automation)? Those
  typically run as real host root and rely on the current `uid=0` ownership
  continuing to mean literal root.

If the mount is shared by other guests or by host-level scripts, **do not**
edit the existing storage's mount options globally — that fixes one
container and silently breaks everything else relying on the old ownership.
Instead, set up a second, independent mount of the same share (Fix path A
below), scoped only to what you're fixing. If this really is a single-use
mount nothing else touches, editing it directly is fine.

## Fix path A (recommended): scoped host-side mount with correct UID/GID

This keeps the fix host-managed and reversible, and doesn't require
installing anything inside the guest. It's usually the better default over
Fix path B.

1. Resolve the host-side uid/gid that correspond to the container's service
   user/group:
   ```
   scripts/map_container_id.sh <vmid> u <container-uid>
   scripts/map_container_id.sh <vmid> g <container-gid>
   ```
   Two variants worth knowing about instead of the service user's own uid/gid:
   - **Map to container root** (`uid=100000,gid=100000` in the common
     default-offset case) if the app runs as root inside the container, or
     you're fine with any root-executed process there getting write. Simpler,
     but broader than scoping to one user/group.
   - **A dedicated shared group** (e.g. create `lxc_shares` inside the
     container with a deliberately chosen gid, add every user that needs
     write to it) instead of piggybacking on whatever gid an app package
     happened to create. Scales better when multiple services in one
     container, or multiple containers with a shared uid/gid convention
     (e.g. the linuxserver.io-style `PUID`/`PGID=1000`), all need write to
     the same mount.
2. If a Proxmox `cifs:` storage entry for this server/share already exists,
   reuse its credentials instead of asking the user to retype them —
   username lives in `/etc/pve/storage.cfg`, password in
   `/etc/pve/priv/storage/<storeid>.pw` (format `password=...`, root-only).
   **Never echo the password into chat output or a shell command that gets
   logged** — extract it into a shell variable and redirect straight into
   the new credentials file in one step, e.g.:
   ```
   PW=$(grep -oP 'password=\K.*' /etc/pve/priv/storage/<storeid>.pw)
   printf 'username=%s\npassword=%s\n' "<user>" "$PW" > <creds-file>
   chmod 600 <creds-file>
   ```
3. Run `scripts/setup_scoped_cifs_mount.sh` to create the new host mount
   (fstab entry + mountpoint + mount + verification). It's idempotent — it
   refuses to duplicate an existing fstab entry — and it deliberately does
   **not** touch the container config; that part needs your judgment (see
   next step). It always writes credentials to a separate `credentials=`
   file at `chmod 600`, never inline in the fstab options — `/etc/fstab` is
   world-readable (`0644`) by default, so a `username=...,password=...`
   pair written straight into it leaks the share password to any local
   user on the host. This is the single most common mistake in CIFS
   tutorials; don't reproduce it even for a "quick" one-off mount.

   By default it mounts at boot (`_netdev,nofail` — boots fine even if the
   NAS is unreachable, just without the mount). If the NAS is known to be
   flaky or slow to come up, `x-systemd.automount,noauto` is worth using
   instead — it defers the actual mount until something first accesses the
   path, so a dead NAS can't add boot delay at all (relevant on this host
   given the past experience with `pve02` quorum waits stalling boot — see
   the root `CLAUDE.md`). It also adds `noatime` and `nobrl` by default:
   `nobrl` disables CIFS byte-range locking, which some apps (torrent
   clients, anything doing file locking over the network) need or they'll
   see "operation not supported" errors. If you hit "stale file handle"
   errors against a particular NAS, try adding `noserverino` too.
4. Point the container at the new mount. Check which `mpN` slot is free (or
   is the one currently used for this path) and what in-container path the
   app expects — keep that path unchanged so the app doesn't need
   reconfiguring:
   ```
   pct set <vmid> --mpN <new-host-mount>,mp=<same-in-container-path>
   ```
   Note: a Proxmox-managed `mpN` mount point disables that container's
   snapshot capability (`vzdump`/`pct snapshot` won't work while it's
   present). If snapshots on this container matter, the alternative is
   adding the bind mount as a raw `lxc.mount.entry: <host-path>
   <in-container-path> none bind 0 0` line directly in
   `/etc/pve/lxc/<vmid>.conf` instead of using `mpN` — same effect, but
   outside Proxmox's mount-point bookkeeping so snapshots keep working.
5. Reboot the container — `pct reboot <vmid>` (note: `pct` has no `restart`
   subcommand, only `reboot`). A hot `pct set` alone doesn't reliably
   refresh an already-mounted bind mount inside a running container.
6. Verify with a real write, as the actual service user — not as root, and
   not just an `ls -ld` check, since a group-writable mount can look right
   in a directory listing while the specific user still can't write:
   ```
   pct exec <vmid> -- su -s /bin/sh <service-user> -c \
     'touch <path>/.write_test && echo WRITE_OK && rm <path>/.write_test'
   ```

## Fix path B (alternative): mount CIFS directly inside the container

Sometimes preferable when you want the fix fully self-contained per
container, with no host-side state at all (e.g. the container might migrate
to a different host later, or you don't want to touch `/etc/fstab` on the
Proxmox node). Trade-off: needs a package install and a reboot for the
capability flag, and credentials live inside the guest instead of centrally
on the host.

1. Add the capability flag and reboot:
   ```
   pct set <vmid> --features <existing-features>,mount=cifs
   pct reboot <vmid>
   ```
2. Inside the container: `apt-get install -y cifs-utils`.
3. Create a credentials file inside the container (same never-echo caution
   as above) and an `/etc/fstab` entry — but here use the container's *own*
   uid/gid directly (e.g. `uid=110,gid=118`), no +100000 offset, since this
   mount is entirely inside the container's own user namespace.
4. If a host-side `mpN` bind-mount currently occupies the same in-container
   path, remove it first (`pct set <vmid> --delete mpN`) so it doesn't
   shadow the new mount.
5. `mount -a` inside the container, then verify the same way as step 6
   above.

If `mount -a` fails inside the container even with the feature flag set,
check `dmesg`/`journalctl -xe` inside the container for AppArmor denials
before concluding the container needs to be privileged — it shouldn't.
`features: mount=cifs` exists specifically so this works unprivileged; a
failure here is almost always a missing package, wrong credentials, or a
typo'd fstab line, not a fundamental privilege gap.

## After the fix

- A raw `/etc/fstab` entry and credentials file on the Proxmox host (Fix
  path A) are **not** captured by Proxmox's own config backups — they live
  outside `/etc/pve` and `pvesm`. If this host ever gets rebuilt from a
  backup, this mount won't come back on its own. Note it somewhere durable
  (the project's infra docs/CLAUDE.md, a runbook, etc.) — path, source
  share, and which container(s) depend on it.
- If you went with Fix path A and are tempted to reuse the same scoped mount
  for a second container later, that's fine — just re-run step 4
  (`pct set ... --mpN`) for the other container's `.conf`, no need to
  create yet another mount unless the two containers need genuinely
  different uid/gid ownership. This only works cleanly when every container
  sharing the mount agrees on the same writing uid/gid (this is exactly why
  the linuxserver.io images standardize on `PUID`/`PGID` env vars — it
  makes "one mount, several containers" trivial). If they don't agree,
  give each its own scoped mount rather than trying to force one mount to
  satisfy conflicting ownership needs.
