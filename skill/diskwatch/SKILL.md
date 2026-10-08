---
name: diskwatch
description: Analyse disk space with diskwatch, a cached whole-disk index (duc) with snapshots and growth reports, on macOS (Diskwatch.app; app-usage, cloud-drive and APFS checks) and on Debian/Proxmox servers (systemd; LVM/ZFS/Proxmox storage, cleanup and package reports). Use whenever the user asks what is taking disk space, why a disk or server is full or filling up, what grew recently, what to clean up, which apps or packages are unused, how much space cloud drives use locally, thin-pool or VM disk usage, APFS volumes and reserves, or to install, schedule, run, monitor or troubleshoot diskwatch. Prefer it over ad-hoc du/find walks, which are slow and miss platform pitfalls.
---

# diskwatch

diskwatch keeps a cached index of the whole disk (duc database) and dated folder-size
snapshots. Queries read the index and are instant; a full scan takes 15–30 minutes at
background priority. Never walk the disk with `du`/`find` when the index can answer.

## Workflow

1. **Overview first**: `scripts/overview.sh` (macOS, ≈ 10 s, read-only): free space, APFS
   reserves, index age, largest folders in `/` and `~`, common space hogs, growth since the
   last scan, cloud drives, unused large apps. `--brief` for the first five sections.
   On Linux: `diskwatch status`, `diskwatch report`, `sudo diskwatch storage`.
2. **Drill down** with the index. Do not run `diskwatch ui`/`gui` (interactive; an agent
   cannot drive them); suggest them to the user (`ui` has vim keys, `i` = file info).
   - `diskwatch ls PATH [N]` largest children; `diskwatch du PATH...` sizes of paths;
     `diskwatch ls -a PATH` apparent sizes (placeholders, sparse files).
3. **What changed**: `diskwatch report [N]`, `diskwatch history PATH`, `diskwatch history`
   (free space per scan). Lower the threshold with `DISKWATCH_MIN_DELTA_MB=20`.
4. **Apps / packages**: macOS `diskwatch apps [--days N]` ("no data" ≠ unused; trust it
   only after 30 days of sampling); Linux `diskwatch pkgs`.
5. **Cloud drives** (macOS): `diskwatch cloud`, `diskwatch cloud scan`.
6. **Report** sizes with their source (index date). Separate "safe to clear" from "needs
   the user's decision", and give exact commands. Never delete without explicit
   confirmation; system locations need `sudo`, which the user runs.

## Scanning and scheduling

- Rescan only when the index is stale (> 48 h), after big cleanups, or when asked. Run
  `diskwatch scan` in the background and follow it with `diskwatch progress` (one line with
  a percentage; capped at 99.9 % until done). The index is swapped in only on completion.
- macOS schedule: `diskwatch schedule` (show), `diskwatch schedule scan daily HH:MM |
  weekly DAY HH:MM | off`, `diskwatch schedule sample MIN|off`. The app's agent runs
  `diskwatch tick` every 5 minutes. Linux: systemd timers (`diskwatch status`).
- If scheduled macOS scans stall, check Full Disk Access as the app:
  `open -a Diskwatch --args fda-check; cat ~/.local/share/diskwatch/fda-check`.

## Reading the numbers

- macOS roots: `/` (= `/System/Volumes/Data`) and each local `/Volumes/*`. Excluded by name:
  `CloudStorage`, `Mobile Documents`, `Volumes`.
- Index total > reality is normal (APFS clones count per copy); index total < `df` used is
  normal (root-only folders, snapshots, swap, purgeable space). If totals exceed the disk
  size or a scan runs far past 30 min, read `references/macos-gotchas.md` §1 first.
- Before suggesting deletions, for APFS volume/reserve questions, cloud placeholders or odd
  tool behaviour, read `references/macos-gotchas.md`. For servers, read
  `references/linux.md`.

## Reference

`diskwatch help` lists every command. Data lives in `~/.local/share/diskwatch` (macOS) or
`/var/lib/diskwatch` (Linux). Full reference: the project's `docs/API.md`.
