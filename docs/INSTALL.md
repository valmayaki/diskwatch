# Installing diskwatch

- [System requirements](#system-requirements)
- [macOS](#macos): [from a release](#macos-from-a-release) · [from source](#macos-from-source) · [signing](#optional-stable-signing) · [uninstall](#macos-uninstall)
- [Linux (Debian / Proxmox)](#linux-debian--proxmox): [single host](#single-host) · [Ansible](#many-hosts-ansible) · [vim-key browser](#optional-vim-key-browser-duc-ui) · [uninstall](#linux-uninstall)
- [Agent skill](#agent-skill)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)

## System requirements

### macOS

| | Runtime (release app) | Building from source |
|---|---|---|
| macOS | **12 Monterey or later**, Apple silicon or Intel | any recent macOS |
| Tools | none beyond macOS (`/bin/bash` 3.2, `launchctl`, `mdls`, `diskutil`, `taskpolicy`, `script`) | Xcode Command Line Tools (`xcode-select --install`): `clang`, `swiftc`, `lipo`, `codesign`; plus `curl`, `python3`, `shasum` |
| Libraries | macOS system libraries only (`libSystem`, `libz`, `libbz2`, `libncurses`); duc and Tokyo Cabinet are bundled | sources downloaded and checksum-verified by `build-duc.sh` |
| Optional | Homebrew `duc` for the graphical `diskwatch gui` (`brew install duc`) | `shellcheck` for linting |
| Disk / memory | app 1.8 MB; index ≈ 90 MB for a 500 GB disk; ≈ 7 MB per daily snapshot (last 90 kept); scans peak ≈ 40 MB RAM | – |

### Linux

| | Runtime | Building duc-ui |
|---|---|---|
| Distribution | Debian 12 (bookworm) or 13 (trixie), including Proxmox VE 8 / 9; other Debian derivatives with `duc` ≥ 1.4.4 should work | – |
| Packages | `duc` (pulls in `libtokyocabinet`, `libncursesw`), `bash` ≥ 4, `util-linux` (`findmnt`, `script`, `ionice`), `systemd`, `coreutils`, `gawk`/`mawk` | Docker (local or `DOCKER_HOST`) |
| Optional | `lvm2`, `zfsutils-linux`, Proxmox `pvesm` (used by `storage` when present); `docker`, `snap`, `flatpak` (used by `cleanup` / `pkgs` when present) | – |
| Privileges | `scan`, `sample`, `install` need root; reports work for any user | – |
| Ansible (optional) | ansible-core ≥ 2.15 on the controller; `python3` on hosts | – |

## macOS

### macOS from a release

1. Download `Diskwatch-<version>-macos-universal.zip` from the
   [Releases page](https://github.com/valmayaki/diskwatch/releases) and check it:
   ```sh
   shasum -a 256 -c SHA256SUMS --ignore-missing
   ```
2. Put the app in **your** Applications folder (it runs per user):
   ```sh
   mkdir -p ~/Applications
   unzip Diskwatch-*-macos-universal.zip -d ~/Applications
   ```
3. Release builds are ad-hoc signed, not notarised, so Gatekeeper blocks them by default.
   Clear the download quarantine (or right-click the app → Open once):
   ```sh
   xattr -dr com.apple.quarantine ~/Applications/Diskwatch.app
   ```
4. Install the command-line wrapper and the background agent:
   ```sh
   ~/Applications/Diskwatch.app/Contents/MacOS/diskwatch-launcher install
   ```
   This writes `~/.local/bin/diskwatch` (add `~/.local/bin` to your `PATH` if needed),
   registers the agent, and prints the schedule. On macOS 13+ the agent may appear under
   **System Settings → General → Login Items**; approve it there if asked.
5. Grant **Full Disk Access**: System Settings → Privacy & Security → Full Disk Access →
   add `~/Applications/Diskwatch.app` and switch it on. Without it, scheduled scans stop at
   a "would like to access Documents" prompt. Verify:
   ```sh
   open -a Diskwatch --args fda-check && sleep 2 && cat ~/.local/share/diskwatch/fda-check
   ```
6. First index (≈ 15–30 min, background priority) and a look at the result:
   ```sh
   diskwatch scan && diskwatch ls / 15
   ```

### macOS from source

```sh
git clone https://github.com/valmayaki/diskwatch && cd diskwatch
macos/app/build-duc.sh      # universal duc + Tokyo Cabinet, macOS 12 minimum (≈ 30 s)
macos/app/build-app.sh      # → ~/Applications/Diskwatch.app
~/Applications/Diskwatch.app/Contents/MacOS/diskwatch-launcher install
```

Then grant Full Disk Access (step 5 above). `build-app.sh PATH` builds elsewhere (a release
or staging build): it signs ad-hoc and does not touch the installed agent.

The plain script also runs without the app (`macos/diskwatch install` uses per-task
LaunchAgents and Homebrew `duc`), but scheduled scans then run as `bash`, which macOS will
not let read protected folders without granting `bash` itself Full Disk Access. Prefer the app.

### Optional: stable signing

Ad-hoc signatures change with every build, and macOS ties Full Disk Access to them, so each
rebuild needs the app re-added. A local code-signing certificate fixes that:

```sh
macos/app/create-signing-cert.sh     # once; asks for your password to trust the cert
macos/app/build-app.sh               # now signs with "Diskwatch Local Code Signing"
```

Full Disk Access then follows the certificate and survives rebuilds.

### macOS uninstall

```sh
diskwatch uninstall                          # agent + ~/.local/bin/diskwatch
rm -rf ~/Applications/Diskwatch.app
rm -rf ~/.local/share/diskwatch              # index, snapshots, schedule (optional)
```

Remove the Full Disk Access entry in System Settings as well.

## Linux (Debian / Proxmox)

### Single host

```sh
sudo apt install duc
curl -fsSLO https://github.com/valmayaki/diskwatch/releases/latest/download/diskwatch-linux
sudo install -m 755 diskwatch-linux /usr/local/bin/diskwatch
sudo diskwatch install        # optional argument: scan hour, default 3
sudo diskwatch scan           # first index
diskwatch report
```

`install` creates `diskwatch-scan.timer` (nightly, `Persistent=true`, randomised by 15 min)
and `diskwatch-sample.timer` (every 15 min). Settings live in `/etc/default/diskwatch`
(see [API.md](API.md#linux-configuration)).

### Many hosts (Ansible)

```sh
cd linux/ansible
cp inventory.example.yml inventory.yml      # your hosts, group diskwatch_hosts
ansible-playbook -i inventory.yml playbook-diskwatch.yml --check --diff
ansible-playbook -i inventory.yml playbook-diskwatch.yml -e diskwatch_first_scan=true
```

Role variables and tags: [linux/ansible/roles/diskwatch/README.md](../linux/ansible/roles/diskwatch/README.md).

### Optional: vim-key browser (duc-ui)

Debian's `duc ui` works, but the release's `duc-ui` adds vim keys and the `i` info popup.
Download the build for your release and architecture, or build it:

```sh
sudo install -m 755 duc-ui-trixie-amd64 /usr/local/bin/duc-ui     # Debian 13
linux/build-duc-ui.sh                                              # or build (Docker)
```

`diskwatch ui` uses `duc-ui` when present. The Ansible role installs it automatically when
`roles/diskwatch/files/duc-ui-<release>` exists (`build-duc-ui.sh` puts it there).

### Linux uninstall

```sh
sudo diskwatch uninstall          # timers and /usr/local/bin/diskwatch
sudo rm -rf /var/lib/diskwatch    # data (optional)
```

With Ansible: `-e diskwatch_state=absent`.

## Agent skill

```sh
mkdir -p ~/.claude/skills && cp -R skill/diskwatch ~/.claude/skills/
```

See [SKILLS.md](SKILLS.md).

## Upgrading

- **macOS app:** replace `~/Applications/Diskwatch.app`, run `diskwatch-launcher install`
  again, and re-add Full Disk Access if the app is ad-hoc signed. Data and schedule are kept.
- **Linux:** replace `/usr/local/bin/diskwatch` (or re-run the playbook with
  `-t diskwatch_script`). Timers and data are kept.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Scheduled scan never finishes; macOS prompt "would like to access Documents" | Full Disk Access missing or for an older build. Re-add the app; check with `fda-check`. |
| Agent never runs; `launchctl print gui/$UID/com.diskwatch.agent` shows exit 78 or `OS_REASON_CODESIGNING` | The app was rebuilt after registration. Run `diskwatch-launcher install` (it re-registers and falls back to a LaunchAgent file if launchd rejects the bundled agent). |
| "Diskwatch can't be opened" | Gatekeeper quarantine on an unsigned download: `xattr -dr com.apple.quarantine ~/Applications/Diskwatch.app`. |
| `diskwatch report` totals larger than the disk | APFS clones are counted per copy; see [ARCHITECTURE.md](ARCHITECTURE.md#accounting-pitfalls). |
| Index total smaller than `df` used | Root-only folders, snapshots, swap and purgeable space are not indexed; normal. |
| `diskwatch ui` hangs or shows nothing | Terminal too small, or an old launcher; rebuild the app. On Linux, `TERM` must be set. |
| Linux scan skips a folder | Bind mounts are skipped on purpose (`diskwatch roots` lists them); add with `DISKWATCH_PATHS`. |
