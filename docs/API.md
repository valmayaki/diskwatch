# diskwatch reference

The interface other people and programs use: commands, configuration, environment
variables, data files, the macOS launcher, and the browser keys. Paths are written for a
default install.

- [Conventions](#conventions)
- [macOS commands](#macos-commands)
- [Linux commands](#linux-commands)
- [Configuration](#configuration): [macOS schedule](#macos-schedule) · [Linux](#linux-configuration) · [environment variables](#environment-variables)
- [Data files](#data-files)
- [macOS launcher interface](#macos-launcher-interface)
- [Browser keys (`diskwatch ui`)](#browser-keys-diskwatch-ui)
- [Integrating](#integrating)

## Conventions

- **Index-only commands** (`report`, `history`, `ls`, `du`, `roots`, `ui`) read the cached
  index and never walk the disk; they return in well under a second.
- **Paths** you pass are what you see in the shell (`/`, `~/Library`, `/Volumes/Disk`).
  On macOS, `/` is indexed as `/System/Volumes/Data` (the data volume) and mapped back.
- **Sizes** are allocated (on-disk) bytes unless a command says *apparent*; output uses
  binary units (`1.5G` = 1.5 GiB).
- **Exit status:** `0` on success, `1` on errors or invalid usage (message on stderr,
  prefixed `diskwatch:`). `scan` exits non-zero when indexing produced no database.
- `diskwatch help` (or an unknown command) prints the command list.

## macOS commands

| Command | Description |
|---|---|
| `scan` | Index the data volume and every local volume in `/Volumes` at background priority (`taskpolicy -b`, `nice 19`) into a temporary database, swap it in, save a snapshot, check alerts. ≈ 15–30 min for 500 GB. |
| `progress [--watch]` | One progress line for a running scan: bar, percent (capped at 99.9 % until done), bytes indexed / expected, files, elapsed. `--watch` refreshes every 2 s. |
| `report [N]` | Folders that grew or shrank by ≥ `DISKWATCH_MIN_DELTA_MB` between the last two snapshots, largest growth first (default 20 rows). With one snapshot: the largest folders. |
| `history [PATH]` | `PATH`'s size in every snapshot; without `PATH`, free space at each scan. |
| `ls [-a] [PATH] [N]` | Largest children of `PATH` (default `/`, 20 rows). `-a`: apparent sizes. |
| `du PATH...` | Size of each path from the index; `-` when not indexed. |
| `roots` | Indexed roots and their totals. |
| `ui [PATH]` | Interactive browser of the index (see [keys](#browser-keys-diskwatch-ui)). Default `/`. |
| `gui [PATH]` | Graphical sunburst (needs Homebrew `duc` with its GUI). |
| `cloud [scan\|show\|progress]` | Cloud drives (`~/Library/CloudStorage/*`, `~/Library/Mobile Documents`): local disk used vs size in the cloud; flags folders macOS left behind (`Name (DD-MM-YYYY HH:MM)`). `scan` indexes them separately (`cloud.db`). |
| `apps [--days N]` | Applications by last use (Spotlight `kMDItemLastUsedDate` or diskwatch's own run samples), size, launch count, hours seen running. `← candidate` marks apps ≥ 500 MB unused ≥ 90 days (apps with no record only after 30 days of sampling). |
| `sample` | Record which `.app` bundles are running (the agent runs this on the sampling schedule). |
| `schedule [...]` | Show or set the schedule; see [macOS schedule](#macos-schedule). |
| `tick` | Run whatever the schedule says is due. The background agent runs it every 5 minutes. |
| `fda-check` | Report whether the current process has Full Disk Access (reads `~/Library/Mail`). Run as the app: `open -a Diskwatch --args fda-check`. Writes `fda-check`. |
| `install [HOUR]` | From the app: write `~/.local/bin/diskwatch` (a wrapper that runs the app), remove old per-task LaunchAgents, register the background agent; optional `HOUR` sets a daily scan. From the plain script: per-task LaunchAgents. |
| `uninstall` | Unregister the agent, remove LaunchAgents and the CLI wrapper. Data is kept. |
| `status` | Data size, free space, snapshot count, apps seen, agent state, schedule, last log lines. |

## Linux commands

Reports work for any user; `scan`, `sample`, `install`, `uninstall` need root.

| Command | Description |
|---|---|
| `scan` | Index every mounted local filesystem (ext2-4, xfs, btrfs, zfs, f2fs, vfat, exfat, jfs, reiserfs, bcachefs) with `-x` per root, at idle I/O priority. Bind mounts and duplicate mounts are skipped. |
| `progress [--watch]`, `report [N]`, `history [PATH]`, `ls [-a] [PATH] [N]`, `du PATH...` | As on macOS. |
| `roots` | Indexed roots, plus bind mounts that were left out (and why). |
| `ui [PATH]` | Browser; uses `duc-ui` (vim keys, info popup) when installed, else `duc ui`. |
| `storage` | What file scans cannot see: `df`, Proxmox `pvesm status` and the largest guest volumes, LVM volume groups and thin pools (`data%`/`meta%`), ZFS pools and datasets (incl. `usedbysnapshots`). |
| `cleanup` | Read-only reclaim hints with the command to run: journald, APT cache and autoremove, installed kernels (marks the running one), large logs, coredumps, Docker (`system df`, oversized container logs), snap revisions, Flatpak runtimes, Proxmox dumps/templates, ZFS snapshots. Changes nothing. |
| `pkgs [N]` | Largest installed packages with a last-used estimate (newest access time of the package's executables under `relatime`, or the last run sample), plus snaps and Flatpaks. |
| `sample` | Record which packages own the executables running now. |
| `install [HOUR]` / `uninstall` | Create / remove `diskwatch-scan.{service,timer}` and `diskwatch-sample.{service,timer}`. |
| `status` | Data size, index age, roots, timers, last journal lines. |

## Configuration

### macOS schedule

```sh
diskwatch schedule                           # show: scan schedule, next run, sampling, agent
diskwatch schedule scan daily HH:MM          # e.g. daily 03:00
diskwatch schedule scan weekly DAY HH:MM     # DAY: sun mon tue wed thu fri sat
diskwatch schedule scan off
diskwatch schedule sample MINUTES            # app sampling interval, 5–1440
diskwatch schedule sample off
```

Stored in `~/.local/share/diskwatch/schedule.conf` (outside the app bundle, so changing
it never touches the app's signature). Defaults: `daily 03:00`, sampling every 15 minutes.
A scan is due when the last scan started before the most recent scheduled time, so a run
missed while the Mac slept happens at the next 5-minute check.

### Linux configuration

`/etc/default/diskwatch` (read by the scan service and by alerting):

```sh
DISKWATCH_FREE_ALERT_PCT=10          # alert when a filesystem has less free space (%)
DISKWATCH_GROWTH_ALERT_GB=5          # alert when a folder grows this much between scans
DISKWATCH_EXCLUDE=""                 # colon-separated directory names to skip
DISKWATCH_NOTIFY_CMD=""              # receives each alert on stdin, e.g.
                                     #   curl -s -d @- https://ntfy.sh/<topic>
```

Alerts always go to the journal: `journalctl -t diskwatch`. The scan time is the timer's
`OnCalendar` (`sudo diskwatch install HOUR`, or the Ansible variable `diskwatch_scan_hour`).

### Environment variables

| Variable | Platform | Default | Meaning |
|---|---|---|---|
| `DISKWATCH_DATA` | both | `~/.local/share/diskwatch` (macOS), `/var/lib/diskwatch` (Linux) | Data directory |
| `DISKWATCH_PATHS` | both | auto | Colon-separated scan roots, replacing auto-detection |
| `DISKWATCH_EXCLUDE` | both | – | Colon-separated directory **names** to skip (duc matches names, not paths) |
| `DISKWATCH_LEVELS` | both | `4` | Folder depth kept in snapshots (affects `report`/`history`) |
| `DISKWATCH_MIN_DELTA_MB` | both | `200` | Smallest change shown by `report` |
| `DISKWATCH_GROWTH_ALERT_GB` | both | `5` | Growth alert threshold |
| `DISKWATCH_FREE_ALERT_GB` | macOS | `20` | Low-free-space notification threshold |
| `DISKWATCH_FREE_ALERT_PCT` | Linux | `10` | Low-free-space alert threshold |
| `DISKWATCH_NOTIFY_CMD` | Linux | – | Command that receives alert text on stdin |
| `DISKWATCH_APP` | macOS | set by the launcher | Path of the running app bundle (internal) |
| `DISKWATCH_FORCE_LEGACY` | macOS | – | `1`: the launcher uses the LaunchAgent file instead of SMAppService |
| `DISKWATCH_SIGN_ID` | macOS build | `Diskwatch Local Code Signing` | Code-signing identity for `build-app.sh` |

On macOS, names excluded by default: `CloudStorage`, `Mobile Documents` (indexed separately
by `cloud scan`) and `Volumes` (breaks a firmlink loop; see
[ARCHITECTURE.md](ARCHITECTURE.md#the-firmlink-loop)).

## Data files

All plain text unless noted; tab-separated (`\t`) where columns are listed. Epoch times are
Unix seconds.

| File | Platform | Format |
|---|---|---|
| `duc.db` | both | duc index (Tokyo Cabinet). Read it with `duc ls -d duc.db PATH`, `duc info -d duc.db`. Replaced atomically after each scan. |
| `snapshots/YYYY-MM-DDTHHMM.tsv` | both | `bytes	path` for every root and folder down to `DISKWATCH_LEVELS`. Last 90 kept. |
| `free.tsv` | both | `epoch	free_bytes` per scan |
| `last_total` | both | Bytes indexed by the last scan (progress denominator) |
| `progress.log` | both | Raw `duc index -p` output of the running scan (removed when done) |
| `diskwatch.log` | macOS | `YYYY-MM-DD HH:MM:SS message` (scan start/done, ticks). Linux logs to the journal. |
| `schedule.conf` | macOS | `scan=daily 03:00` · `sample=15` |
| `last_scan_start`, `last_sample` | macOS | Epoch of the last scan start / app sample |
| `apps.tsv` | macOS | `bundle_path	samples	first_seen_epoch	last_seen_epoch` |
| `cloud.db`, `cloud-progress.log` | macOS | Cloud-drive index and its progress |
| `fda-check` | macOS | `YYYY-MM-DD HH:MM:SS granted\|denied <app path\|cli>` |
| `pkg-seen.tsv` | Linux | `package	samples	first_seen_epoch	last_seen_epoch` |
| `exe-pkg.tsv` | Linux | `executable_path	package` (cache of `dpkg -S`) |

Example: total of `~/Library` in the last two snapshots:

```sh
cd ~/.local/share/diskwatch/snapshots
for f in $(ls -1 | tail -2); do awk -F'\t' -v p="$HOME/Library" '$2==p{print FILENAME, $1}' "$f"; done
```

## macOS launcher interface

`Diskwatch.app/Contents/MacOS/diskwatch-launcher`:

| Invocation | Result |
|---|---|
| `diskwatch-launcher <command> [args]` | Runs the bundled script with `<command>` as a child process (same process group, so terminal UIs and Ctrl-C work). Exit status is the script's. |
| `diskwatch-launcher --register` | Registers the background agent `com.diskwatch.agent` (`tick` every 5 min). macOS 13+: SMAppService, then verifies the first run and falls back to `~/Library/LaunchAgents/com.diskwatch.agent.plist` if launchd rejects it. macOS 12: the LaunchAgent file. Prints `enabled`, `requires-approval`, or `enabled (LaunchAgent …)`. |
| `diskwatch-launcher --unregister` | Removes the agent (both mechanisms). Prints `not-registered`. |
| `diskwatch-launcher --agent-status` | Prints exactly one of `enabled`, `requires-approval`, `not-registered`, `not-found`. |

## Browser keys (`diskwatch ui`)

| Keys | Action |
|---|---|
| `j` / `k`, ↓ / ↑ | move |
| `l`, →, Enter / `h`, ←, Backspace | open folder / parent folder |
| `g`, `0`, Home / `G`, `$`, End | top / bottom |
| Ctrl-D / Ctrl-U, Ctrl-F / Ctrl-B, PgDn / PgUp | half page / page |
| `i` | info popup: path, type, on-disk and apparent size, file count, live modified time, owner, mode |
| `o` | reveal in Finder (macOS) / `xdg-open` (Linux); also from the info popup |
| `a` / `c` / `b` | apparent size / file count / exact bytes |
| `n` / `v` | sort by name / toggle size graph |
| `?` | help |
| `q`, Esc | quit |

## Integrating

- **Machine-readable sizes:** `duc ls -b -d <data>/duc.db <path>` prints `bytes name` lines.
- **Progress:** `diskwatch progress` prints one line containing `NN.N%`, suitable for
  progress-bar wrappers (it caps at 99.9 % until the scan has finished).
- **Alerts on Linux:** set `DISKWATCH_NOTIFY_CMD`; the text arrives on stdin.
- **Snapshots** are plain TSV and safe to read while a scan runs (each is written once).
