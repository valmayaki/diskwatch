# Diskwatch.app (macOS)

Sources for the self-contained macOS app: universal (arm64 + x86_64), macOS 12+.

| File | Purpose |
|---|---|
| `launcher.swift` | `diskwatch-launcher`: runs the bundled script as a child (`posix_spawn`, same process group); `--register` / `--unregister` / `--agent-status` for the background agent |
| `com.diskwatch.agent.plist` | Bundled agent (SMAppService, macOS 13+): `diskwatch tick` every 5 minutes |
| `Info.plist` | Bundle metadata (`com.diskwatch.app`, minimum macOS 12.0) |
| `build-duc.sh` | Universal standalone duc 1.4.6 + Tokyo Cabinet 1.4.48 from pinned, verified sources |
| `build-app.sh` | Assembles and signs the app (`[PATH]`: release build, ad-hoc, leaves the installed agent alone) |
| `create-signing-cert.sh` | Optional local code-signing identity so Full Disk Access survives rebuilds |
| `make-icon.swift`, `Diskwatch.icns`, `icon-1024.png` | Icon source and outputs |

See [docs/INSTALL.md](../../docs/INSTALL.md) for building and installing and
[docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md#macos-app) for how it works.
