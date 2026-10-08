# diskwatch on Linux (Debian / Proxmox)

Read when working on servers. Reach hosts over SSH; use `sudo -n` for root-only commands
when you are not root.

## Commands

Reports read `/var/lib/diskwatch` and work as any user; `scan`, `sample`, `install` need root.

- `diskwatch report | history | ls | du | roots | progress | status` — as on macOS.
- `diskwatch storage` — what the file index cannot see: `pvesm status`, largest guest
  volumes (provisioned size), LVM `data%` of thin pools and thin volumes, ZFS pools and
  `usedbysnapshots`. Use it first on Proxmox: VM/CT disks on LVM-thin or zvols are not files.
- `diskwatch cleanup` — read-only reclaim hints with commands: journald, apt cache and
  autoremove, installed kernels (and which runs), large logs, coredumps, Docker
  (`docker system df`, big container json logs), snap revisions, vzdump backups, ZFS snapshots.
- `diskwatch pkgs [N]` — largest packages with last-used (executable atime under relatime,
  plus 15-minute run samples).
- Start a scan without waiting: `sudo systemctl start --no-block diskwatch-scan`, then poll
  `diskwatch progress`. Alerts: `journalctl -t diskwatch`.

## Deployment

The repository's Ansible role (`linux/ansible`) installs the script, `duc`, `duc-ui` and the
timers. Tags: `diskwatch`, `diskwatch_{install,packages,script,ui,config,systemd,scan,remove}`;
`-t diskwatch_script` pushes only the script; `-e target_hosts=NAME` limits to one host.
Edit the repository copy, run `shellcheck -S warning`, then deploy; do not edit
`/usr/local/bin/diskwatch` on a host.

## Linux specifics

- Roots are mounted local filesystems; `-x` works (no firmlink loop). Bind mounts
  (`findmnt` SOURCE like `/dev/sda4[/sub/dir]`, e.g. host shares bound into a container) are
  not scanned; they belong to the host that owns the device.
- Thin provisioning: freed blocks stay allocated in the pool until trimmed (`pct fstrim
  <id>`; the host `fstrim.timer` does not reach container volumes). A thin volume at 100 %
  `data%` is full from the guest's view; a pool near 100 % stalls every guest on it — flag both.
- Proxmox keeps many `proxmox-kernel-*-signed` packages (≈ 0.6–1 GB each); `apt autoremove`
  trims them. A running kernel older than the newest installed means a reboot is pending.
- Scans run as root, so the index total ≈ `df` used.
