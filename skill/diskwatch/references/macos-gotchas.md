# macOS disk-space gotchas

Read when numbers don't add up, a scan behaves oddly, or before recommending deletions.

## Contents
1. Totals that exceed the disk (clones, firmlink loop)
2. Space the index cannot see
3. APFS containers, volume groups and reserves
4. Cloud-drive placeholders
5. Safe vs unsafe cleanup
6. Tooling pitfalls

## 1. Totals that exceed the disk

- **APFS clones** (`cp -c`, Finder duplicate, Xcode/simulators, Docker, package managers) share blocks.
  Every file walker (`duc`, `du`, Finder) counts each clone in full, so a folder total can exceed
  what deleting it would free. Expect the index to read somewhat higher than `df` used.
  Sparse files are fine: duc counts allocated blocks (a 2 GB sparse image counts as ~16 KB).
- **Firmlink loop**: `/System/Volumes/Data/System` resolves to the real `/System`, whose
  `Volumes/Data` leads back to the start (Data → System → Volumes → Data …). System and data
  volumes share one `st_dev`, so `duc -x` / `du -x` cannot stop it; a walk of
  `/System/Volumes/Data` then counts the disk again and again (seen: 1 TB+ on a 494 GB SSD).
  diskwatch excludes directories named `Volumes` to break it. Symptom: totals growing past the
  disk size; confirm with `lsof -p $(pgrep -x duc)`: a repeating DIR stack of
  `/System/Volumes/Data, /System, /System/Volumes`.

## 2. Space the index cannot see (index total < `df` used)

The gap (tens of GB is normal) is mostly:
- root-only directories (`/private/var/db`, `.Spotlight-V100`, `.fseventsd`,
  `.DocumentRevisions-V100`, other users' homes): needs `sudo`, which the agent normally lacks;
- APFS local snapshots and purgeable space: `tmutil listlocalsnapshots /`,
  `diskutil apfs list` (Snapshot lines); purgeable shows in Finder's Get Info, not `df`;
- cloud-drive downloads, which the main scan excludes (use `diskwatch cloud`).

Say "unaccounted, likely root-only/system-managed" rather than guessing a cause.

## 3. APFS containers, volume groups, reserves

- All volumes in one container share its free space. `diskutil apfs list <container>` shows
  `Capacity Reserve`/`Capacity Quota` per volume and `Capacity Not Allocated` for the container.
- A volume with a **reserve** keeps that much space for itself even when unused; deleting files on
  it frees nothing for siblings until its usage drops below the reserve.
- A reserve can only be set when the volume is created (`diskutil apfs addVolume … -reserve`);
  nothing changes it afterwards, Recovery mode included. Removing it means backing up the data,
  deleting the volume (`diskutil apfs deleteVolume`) and restoring. `eraseVolume` also drops the
  reserve but destroys the data. Always get explicit confirmation before either.
- A volume under `/Volumes` may be a partition of the internal SSD, not an external drive: check
  `diskutil info <mount>` → `Device Location: Internal`, `APFS Container:`.

## 4. Cloud-drive placeholders

`~/Library/CloudStorage/*` (Google Drive, OneDrive, Dropbox, iCloudDrive-*) and
`~/Library/Mobile Documents` (iCloud Drive) contain dataless placeholders: apparent size = the
cloud copy, actual size ≈ 0 until downloaded. Compare `duc ls` (actual) with `duc ls -a`
(apparent), or run `diskwatch cloud`. Folders renamed `Name (DD-MM-YYYY HH:MM)` are copies
macOS left behind when an account was removed or re-added. They are usually tiny (`.DS_Store`,
Office `~$` lock files) but check their contents before suggesting removal.

## 5. Safe vs unsafe cleanup

Reasonably safe (regenerated on demand); still confirm with the user first:
- `~/Library/Caches/*`, `~/.cache`, `~/.npm` (`npm cache clean --force`), `brew cleanup`,
  `~/.gradle/caches`, Xcode `~/Library/Developer/Xcode/DerivedData`,
  unused simulator runtimes (`xcrun simctl runtime list` / `delete <id>`),
  `xcrun simctl delete unavailable`, Ollama models (`ollama list`, `ollama rm`),
  `node_modules` in inactive projects, `docker system df` → `docker system prune`.
- `/Users/Shared/Previously Relocated Items*`: macOS update leftovers (root-owned, needs sudo).

Never delete without explicit confirmation, and never touch: anything under `/System`,
`~/Library/Mobile Documents` / `CloudStorage` contents (deletes cloud copies too),
`~/Library/Application Support/<app>` while the app is in use, Photos/Mail libraries,
`.git` directories, or anything whose purpose is unclear: report it instead.
For app removal prefer a proper uninstaller (Pearcleaner, AppCleaner, or the vendor's) so
launch agents/daemons go too; check `/Library/LaunchAgents`, `/Library/LaunchDaemons`,
`~/Library/LaunchAgents` afterwards.

## 6. Tooling pitfalls

- `duc` only emits `-p` progress on a TTY; diskwatch wraps it in `script -q` to capture it.
- `duc -e NAME` matches entry names (fnmatch), not paths, and never the root arguments
  themselves; `-e Volumes` does not skip a `/Volumes/<disk>` root.
- macOS has no `timeout`; use `perl -e 'alarm N; exec @ARGV' cmd …`.
- Under `set -o pipefail`, `cmd | head` can exit 141 (SIGPIPE); drain with
  `awk 'NR<=n'` instead.
- Copying many small files to SMB/NAS is extremely slow (≈31k files took ~2 h); archive first
  (`tar`), or exclude `node_modules`.
- `brew install X` can upgrade dozens of dependents; use
  `HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1`.
