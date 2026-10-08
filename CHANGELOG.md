# Changelog

All notable changes are documented here. The project follows
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-08

First public release.

### macOS
- **Diskwatch.app**: self-contained, universal (Apple silicon + Intel), macOS 12 Monterey
  and later. Bundles the diskwatch program and a standalone duc 1.4.6 (Tokyo Cabinet linked
  statically; only macOS system libraries).
- Whole-disk cached index of the data volume and local volumes, with snapshots and growth
  reports: `scan`, `report`, `history`, `ls`, `du`, `roots`, `progress`, `status`.
- User-settable schedule (`schedule scan daily|weekly|off`, `schedule sample`) run by a
  single background agent (`tick` every 5 minutes) that catches up after sleep.
  SMAppService on macOS 13+, with automatic fallback to a LaunchAgent file; LaunchAgent on 12.
- Full Disk Access owned by the app; `fda-check`; optional local signing certificate so the
  grant survives rebuilds.
- `apps`: unused applications (Spotlight last-used + run sampling). `cloud`: local vs cloud
  size of iCloud Drive, Google Drive, OneDrive; flags folders left behind.
- Correct APFS accounting: firmlink loop broken, cloud placeholders separated.
- Notifications for low free space and large growth.

### Linux (Debian / Proxmox)
- `diskwatch` for Debian 12/13 and Proxmox VE 8/9 with systemd timers; bind mounts skipped.
- `storage` (Proxmox storages and guest volumes, LVM thin pools, ZFS), `cleanup` (journal,
  apt, kernels, logs, Docker, snap, Flatpak, vzdump, ZFS snapshots), `pkgs` (largest packages
  with last-used estimate).
- Ansible role with per-area tags, check-mode support and idempotent runs.

### Both
- Terminal browser with vim keys (`j/k`, `h/l`, `g/G`, Ctrl-D/U/F/B) and an `i` file-info
  popup (path, type, on-disk/apparent size, file count, live modified time, owner, mode).
- Agent skill (`skill/diskwatch`) for AI coding assistants.

[1.0.0]: https://github.com/valmayaki/diskwatch/releases/tag/v1.0.0
