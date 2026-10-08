# Architecture

- [Overview](#overview)
- [Indexing](#indexing)
- [macOS app](#macos-app): [layout](#layout) · [launcher](#launcher) · [scheduling](#scheduling) · [privacy permissions](#privacy-permissions-tcc) · [compatibility](#compatibility)
- [Linux](#linux)
- [Accounting pitfalls](#accounting-pitfalls): [firmlink loop](#the-firmlink-loop) · [clones](#apfs-clones) · [unindexed space](#space-the-index-cannot-see) · [APFS reserves](#apfs-volume-reserves) · [cloud placeholders](#cloud-drive-placeholders) · [thin provisioning](#thin-provisioning-proxmox)

## Overview

```
 scheduler ──► diskwatch tick/scan ──► duc index (background I/O) ──► duc.db (swapped in atomically)
                                                         │
                                                         └──► snapshots/<time>.tsv  (folder sizes, 4 levels)
 you / agents ──► report · history · ls · du · ui ──► read duc.db and snapshots only
```

diskwatch is a bash program around [duc](https://duc.zevv.nl). duc walks the disk once and
writes directory totals into an on-disk Tokyo Cabinet database, so memory stays small (it
grows with directory depth, not file count) and queries are instant. diskwatch adds what duc
lacks: scheduling, snapshots and diffs, alerts, platform-specific accounting fixes, and
reports for apps, packages, cloud drives and block storage.

## Indexing

- A scan writes to `duc.db.tmp.<pid>` and renames it over `duc.db` only on success, so
  readers always see a complete index, even mid-scan.
- Roots: macOS indexes `/System/Volumes/Data` (everything under `/`) plus each local volume
  mounted in `/Volumes`; Linux indexes every mounted local filesystem. `duc -x` keeps each
  root on its own filesystem; network shares are never device-backed, so never roots.
- After indexing, `duc ls -R --dirs-only -l 4` writes a snapshot TSV; `report` diffs the last
  two, `history` reads one path across all of them.
- `duc -p` only prints progress on a terminal, so scans run under `script(1)` and the
  output is parsed by `progress`.
- Scans run at background priority: `taskpolicy -b` and `nice 19` on macOS,
  `ionice -c3`/`IOSchedulingClass=idle` and `nice 19` on Linux.

## macOS app

### Layout

```
Diskwatch.app/Contents/
  MacOS/diskwatch-launcher                       Swift launcher (universal, macOS 12+)
  Library/LaunchAgents/com.diskwatch.agent.plist  bundled agent (SMAppService, macOS 13+)
  Resources/diskwatch                            the bash program (bash 3.2 compatible)
  Resources/bin/duc, duc-ui                      duc 1.4.6 + patch, static Tokyo Cabinet
  Resources/Diskwatch.icns
```

The app is self-contained: `duc` links only macOS system libraries, the script uses only
tools that ship with macOS. `~/.local/bin/diskwatch` is a two-line wrapper that runs the
launcher.

### Launcher

The launcher starts the bundled script with `posix_spawn` and waits for it.

- **Never `exec`.** macOS attributes a child's file access to the *responsible* process
  that spawned it. If the launcher replaced itself with `/bin/bash`, bash would become
  responsible, and macOS would ask whether "bash" may read Documents.
- **Same process group.** Foundation's `Process` starts children in a new process group;
  an interactive child is then not the terminal's foreground job, and the kernel suspends it
  (SIGTTOU/SIGTTIN) as soon as ncurses touches the terminal. `posix_spawn` without
  `POSIX_SPAWN_SETPGROUP` keeps the group, so `diskwatch ui` and Ctrl-C work.
- It prepends `Resources/bin` and the system directories to `PATH` and sets
  `DISKWATCH_APP`, which the script uses to know it runs bundled.

### Scheduling

One fixed agent, `com.diskwatch.agent`, runs `diskwatch tick` every 5 minutes (and at
load). `tick` reads `schedule.conf`, runs the app sample when its interval has passed, and
runs a scan when the last scan started before the most recent scheduled time. This keeps
the agent definition constant: a user-settable schedule lives outside the signed bundle, and
missed runs (sleep, shutdown) catch up within 5 minutes. launchd does not start a second
instance while a scan is still running.

Registration:

- **macOS 13+** uses `SMAppService.agent(plistName:)` with the plist inside the bundle;
  the agent shows in Login Items and goes away with the app. Background Task Management pins
  a launch constraint to the build that was registered; for a rebuilt, locally signed app it
  can keep a stale record, and launchd then refuses to start the job (exit 78 `EX_CONFIG`
  or `OS_REASON_CODESIGNING`). The launcher therefore verifies the first run and falls back
  to the LaunchAgent file.
- **macOS 12** (and the fallback) writes `~/Library/LaunchAgents/com.diskwatch.agent.plist`
  with the absolute launcher path and loads it with `launchctl bootstrap`.

### Privacy permissions (TCC)

Desktop, Documents, Downloads, Mail, Photos and other locations are protected. Scheduled
scans are started by launchd with Diskwatch.app as the responsible process, so the app
needs **Full Disk Access**. Commands typed in a terminal are attributed to the terminal app
and use its permissions instead.

macOS keys the grant to the app's code identity. An ad-hoc signature is its code hash, which
changes with every build; a certificate signature uses the designated requirement
`identifier "com.diskwatch.app" and certificate leaf = H"…"`, which survives rebuilds.
`create-signing-cert.sh` makes such a certificate locally. `fda-check` reads `~/Library/Mail`
(protected, fails without a prompt) to test the grant as the app.

### Compatibility

- Binaries are universal (`arm64` + `x86_64`) with `LC_BUILD_VERSION minos 12.0`.
  Tokyo Cabinet is compiled from source for that target; Homebrew's copy targets the build
  machine's macOS and would raise the minimum.
- The script avoids bash 4 features: macOS ships bash 3.2, where an empty array under
  `set -u` is an error (`${a[@]+"${a[@]}"}` guards it) and `${p/#$HOME/\~}` keeps the
  backslash.
- `SMAppService` calls are behind `#available(macOS 13.0, *)`.

## Linux

- Root-only scans from systemd: `diskwatch-scan.timer` (`Persistent=true`) and
  `diskwatch-sample.timer`. The index is world-readable, so reports need no root.
- Bind mounts (`findmnt` sources like `/dev/sda4[/sub/dir]`) are not scanned: they belong
  to the host that owns the device, and counting them in a container double-counts them.
- `storage` covers block-level usage that files cannot show (LVM thin, zvols, Proxmox).
- `pkgs` estimates last use from executable access times. With `relatime` an access time is
  updated at most once a day, which is enough for "unused for N days"; with `noatime` the
  report says so and relies on run sampling.
- `duc-ui` is built per Debian release so its index format matches the distribution's `duc`.

## Accounting pitfalls

### The firmlink loop

On macOS 10.15+, `/System/Volumes/Data/System` is a firmlink to the real `/System`, whose
`Volumes/Data` leads back to the start: Data → System → Volumes → Data → … The system and
data volumes report the same `st_dev`, so `duc -x` (and `du -x`) cannot stop the recursion;
an unguarded scan of `/System/Volumes/Data` counts the disk again and again (seen: 1 TB+ on
a 494 GB SSD). diskwatch excludes directories named `Volumes` (duc matches names, never the
root arguments, so `/Volumes/Disk` as a root is still scanned). To diagnose:
`lsof -p $(pgrep -x duc)` shows a repeating stack of `/System/Volumes/Data`, `/System`,
`/System/Volumes`.

### APFS clones

Clones (`cp -c`, Finder duplicate, Xcode, simulators, Docker, package managers) share
blocks. Every file walker counts each clone in full, so a folder total can exceed what
deleting it frees, and index totals can exceed `df`. Sparse files are counted correctly
(allocated blocks).

### Space the index cannot see

Expect the index total to be below `df` used: root-only directories (macOS), local
snapshots and purgeable space (`tmutil listlocalsnapshots /`), and swap (the separate `VM`
volume; `sysctl vm.swapusage`). A growing swap volume is a common reason free space drops
while every folder shrank.

### APFS volume reserves

All volumes in a container share its free space. A volume with a **reserve** keeps that
much for itself even when empty, and deleting files on it frees nothing for the others until
its usage drops below the reserve. A reserve can only be set when a volume is created
(`diskutil apfs addVolume -reserve`), not changed later, Recovery included. A volume under
`/Volumes` may be a partition of the internal disk: check `diskutil info` (`Device
Location`, `APFS Container`).

### Cloud-drive placeholders

`~/Library/CloudStorage/*` and `~/Library/Mobile Documents` hold dataless placeholders:
apparent size is the cloud copy, actual size ≈ 0 until downloaded. `diskwatch cloud`
compares both.

### Thin provisioning (Proxmox)

Blocks freed inside a container on LVM-thin stay allocated in the pool until trimmed, and
the host's `fstrim.timer` does not reach container volumes: run `pct fstrim <id>` (or
schedule it). A thin volume at 100 % `data%` is full from the guest's view even when its
filesystem reports free space; a pool near 100 % stalls every guest on it.
