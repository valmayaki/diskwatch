# Contributing to diskwatch

Thanks for helping. This guide covers setup, layout, conventions, tests, building and
releasing. Small, focused pull requests with a clear description are easiest to review.

## Development setup

| Platform | You need |
|---|---|
| macOS | Xcode Command Line Tools (`xcode-select --install`), `python3`, `curl`; recommended `shellcheck`, `expect` (built in) |
| Linux / role | `shellcheck`, Docker (for `linux/build-duc-ui.sh`), `ansible-core` ≥ 2.15 and `ansible-lint` for the role |

```sh
git clone https://github.com/valmayaki/diskwatch && cd diskwatch
brew install shellcheck          # or: apt install shellcheck
```

Use a throwaway data directory and a small tree while developing, so you never touch your
real index:

```sh
export DISKWATCH_DATA=/tmp/dw-dev DISKWATCH_PATHS=$HOME/Downloads
bash macos/diskwatch scan && bash macos/diskwatch report
```

## Repository layout

```
macos/diskwatch            the macOS program (bash, must run on /bin/bash 3.2)
macos/app/                 Diskwatch.app: Swift launcher, Info.plist, bundled agent,
                           build-duc.sh, build-app.sh, create-signing-cert.sh, icon
linux/diskwatch            the Linux program (bash ≥ 4)
linux/build-duc-ui.sh      duc-ui for Debian releases, in Docker
linux/ansible/             Ansible role, example playbook and inventory
common/duc_vim_patch.py    the duc browser patch (vim keys, info popup), duc 1.4.4–1.4.6
skill/diskwatch/           agent skill
docs/                      install, reference, architecture, skill docs
```

## Conventions

**Shell**

- `set -euo pipefail`; every script must pass `shellcheck -S warning`.
- `macos/diskwatch` runs under macOS's `/bin/bash` **3.2**: no associative arrays,
  `mapfile`, `${var,,}`, or `;&`. Guard possibly-empty arrays as `${a[@]+"${a[@]}"}`
  (3.2 treats them as unset under `-u`). Use `$TILDE` rather than `\~` in replacements.
  Test with `env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash macos/diskwatch …`.
- Under `pipefail`, `cmd | head` can fail with 141 (SIGPIPE); use the `take N` helper.
- macOS has no `timeout(1)`; use `perl -e 'alarm N; exec @ARGV' …`.
- `pgrep -f` matches whole command lines, including shells that merely mention a pattern;
  anchor patterns (`'^duc index .*diskwatch'`).
- Run `script(1)` with stdin from `/dev/null`; it fails on a non-terminal socket.
- Report commands must stay read-only and index-only; anything that walks the disk belongs
  in `scan`.
- Commands that delete or change system state are not added; `cleanup` prints commands
  for the user to run.

**Swift launcher (`macos/app/launcher.swift`)**

- Keep macOS 12 compatible: newer APIs behind `#available`, build with
  `-target <arch>-apple-macos12.0`.
- Start the script with `posix_spawn` in the same process group and wait; never `exec`
  (see [ARCHITECTURE.md](docs/ARCHITECTURE.md#launcher)).

**Ansible role**

- Every task is tagged `diskwatch` plus an area tag; includes pass tags with `apply:`.
- Templates for generated files, handlers for reloads, variables prefixed `diskwatch_`.
- Must pass `ansible-lint` (production profile) and be idempotent (a second run reports
  `changed=0`).

**Documentation**

- User-visible changes update `docs/` (and `docs/API.md` for any command, option,
  variable or file format) and `CHANGELOG.md`.
- No personal data in examples: use `/Users/me`, `host-a`, `/Volumes/Disk`.

## Testing

There is no single test runner yet; run what your change touches.

```sh
# Lint everything
shellcheck -S warning macos/diskwatch linux/diskwatch linux/build-duc-ui.sh \
  macos/app/*.sh skill/diskwatch/scripts/overview.sh

# bash 3.2 compatibility (macOS)
/bin/bash -n macos/diskwatch

# The duc patch applies to every supported duc version
for v in 1.4.4 1.4.5 1.4.6; do
  curl -fsSL https://github.com/zevv/duc/releases/download/$v/duc-$v.tar.gz \
    | tar xzO duc-$v/src/duc/cmd-ui.c > /tmp/cmd-ui-$v.c
  python3 common/duc_vim_patch.py /tmp/cmd-ui-$v.c --macos
done

# Swift launcher type-checks for macOS 12
swiftc -typecheck -target arm64-apple-macos12.0 macos/app/launcher.swift

# Ansible role
cd linux/ansible && ansible-lint playbook-diskwatch.yml roles/diskwatch
```

**Scheduling** (`tick`): use a throwaway `DISKWATCH_DATA`, set `scan daily 00:00`, run
`tick` (scans), run it again (does not), then backdate `last_scan_start` by two days and
run it once more (catches up).

**Interactive browser:** drive it with `expect` and assert on screen content. ncurses
replaces runs of spaces with cursor movements, so match `Label.{0,40}value`, not
`Label +value`:

```tcl
spawn diskwatch ui
expect -re {Users}
send "i"; expect -re { Info }
send "q"
```

**macOS app:** after `build-app.sh`, check `lipo -archs` and `otool -l … | grep minos`
for both binaries, `diskwatch-launcher --agent-status`, and `fda-check` run as the app.

## Building

```sh
macos/app/build-duc.sh        # universal duc (Tokyo Cabinet + duc from pinned, verified sources)
macos/app/build-app.sh [PATH] # app; PATH ≠ ~/Applications/Diskwatch.app = ad-hoc release build
ARCHES="amd64 arm64" linux/build-duc-ui.sh
```

## Releasing (maintainers)

1. Update `CHANGELOG.md` and the version in `macos/app/Info.plist`
   (`CFBundleShortVersionString`, bump `CFBundleVersion`).
2. Build release artifacts into `dist/`:
   ```sh
   macos/app/build-duc.sh && macos/app/build-app.sh "$PWD/dist/Diskwatch.app"
   (cd dist && ditto -c -k --keepParent Diskwatch.app Diskwatch-X.Y.Z-macos-universal.zip)
   ARCHES="amd64 arm64" linux/build-duc-ui.sh
   cp linux/diskwatch dist/diskwatch-linux
   ```
   Add the upstream source tarballs (duc 1.4.4/1.4.5/1.4.6, Tokyo Cabinet 1.4.48) for LGPL
   compliance, then `shasum -a 256 * > SHA256SUMS` in `dist/`.
3. Tag `vX.Y.Z`, push, and create the GitHub release with the notes and `dist/` assets.

## Pull requests

- One topic per PR; describe the problem, the change, and how you tested it (commands and
  results).
- Commit messages: short imperative subject (`Add weekly schedule`, `fix: …`), body for the why.
- By contributing you agree that your contribution is licensed under the MIT licence of this
  project (patches to duc remain under duc's LGPL-3.0).

## Reporting bugs

Include: platform and version (`sw_vers` / `cat /etc/os-release`), how diskwatch is
installed (app, script, Ansible), the command and its output, and for macOS scheduling
issues `diskwatch status` and `launchctl print gui/$UID/com.diskwatch.agent | head -40`.
Remove paths or host names you don't want public.
