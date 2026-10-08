# Third-party notices

diskwatch's own code is MIT-licensed ([LICENSE](LICENSE)). Release binaries contain the
following third-party software.

## duc

- Upstream: <https://github.com/zevv/duc> (Ico Doornekamp and contributors)
- Versions: 1.4.6 (macOS app), 1.4.4 and 1.4.5 (Linux `duc-ui` builds)
- Licence: GNU Lesser General Public License v3.0 —
  [licenses/duc-LGPL-3.0.txt](licenses/duc-LGPL-3.0.txt), which incorporates the
  [GNU GPL v3.0](licenses/GPL-3.0.txt)
- Modifications: `src/duc/cmd-ui.c` is patched by
  [common/duc_vim_patch.py](common/duc_vim_patch.py) (vim keys, `i` info popup, macOS
  reveal-in-Finder). The patch is distributed under duc's LGPL-3.0. Builds are configured
  without the cairo/X11/OpenGL GUI.
- Used as: `Diskwatch.app/Contents/Resources/bin/duc` (and `duc-ui`), and the Linux
  `duc-ui-<release>-<arch>` binaries.

## Tokyo Cabinet

- Upstream: <https://dbmx.net/tokyocabinet/> (FAL Labs, Mikio Hirabayashi)
- Version: 1.4.48
- Licence: GNU Lesser General Public License v2.1 —
  [licenses/tokyocabinet-LGPL-2.1.txt](licenses/tokyocabinet-LGPL-2.1.txt)
- Used as: statically linked into the macOS `duc` (unmodified). The Linux builds link the
  distribution's shared `libtokyocabinet`.

## Corresponding source and relinking

Each GitHub release attaches the exact upstream source archives used (`duc-1.4.4.tar.gz`,
`duc-1.4.5.tar.gz`, `duc-1.4.6.tar.gz`, `tokyocabinet-1.4.48.tar.gz`). The build scripts
in this repository (`macos/app/build-duc.sh`, `linux/build-duc-ui.sh`) download those
archives, verify their SHA-256 checksums, apply the patch and build, so you can rebuild the
binaries, or relink them against a modified Tokyo Cabinet or duc, from source.
