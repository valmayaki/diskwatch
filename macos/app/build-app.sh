#!/usr/bin/env bash
# Build ~/Applications/Diskwatch.app: self-contained, universal (arm64 + x86_64), macOS 12+.
#   Contents/MacOS/diskwatch-launcher                  Swift launcher (child-process runner,
#                                                       --register/--unregister/--agent-status)
#   Contents/Library/LaunchAgents/com.diskwatch.agent.plist   SMAppService agent, only with
#                                                       DISKWATCH_SMAPPSERVICE=1 (Team-ID builds)
#   Contents/Resources/diskwatch, bin/duc, Diskwatch.icns
# Rebuilding changes the ad-hoc signature: re-add the app under Full Disk Access.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
default_app="$HOME/Applications/Diskwatch.app"
app="${1:-$default_app}"
# Building anywhere but the installed location is a release/staging build: sign ad-hoc
# (a local certificate means nothing on other Macs) and leave the installed agent alone.
installed_build=$([[ $app == "$default_app" ]] && echo 1 || echo 0)
min=12.0
mkdir -p "$here/build"

[[ -x "$here/build/duc" ]] || "$here/build-duc.sh"
for a in arm64 x86_64; do
  swiftc -O -target "$a-apple-macos$min" -o "$here/build/launcher.$a" "$here/launcher.swift"
done
lipo -create -output "$here/build/diskwatch-launcher" "$here/build/launcher.arm64" "$here/build/launcher.x86_64"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/bin"
cp "$here/Info.plist" "$app/Contents/Info.plist"
cp "$here/Diskwatch.icns" "$app/Contents/Resources/Diskwatch.icns"
# The bundled SMAppService agent is opt-in: for a locally signed or ad-hoc app, Background Task
# Management keeps re-submitting a stale record of it at every login (see launcher.swift), so
# such builds ship without it and use the LaunchAgent file (com.diskwatch.tick).
if [[ ${DISKWATCH_SMAPPSERVICE:-0} == 1 ]]; then
  mkdir -p "$app/Contents/Library/LaunchAgents"
  cp "$here/com.diskwatch.agent.plist" "$app/Contents/Library/LaunchAgents/"
fi
install -m 755 "$here/../diskwatch" "$app/Contents/Resources/diskwatch"
install -m 755 "$here/build/duc" "$app/Contents/Resources/bin/duc"
ln -s duc "$app/Contents/Resources/bin/duc-ui"
install -m 755 "$here/build/diskwatch-launcher" "$app/Contents/MacOS/diskwatch-launcher"

# Sign inner code first, then the bundle. With the local identity from
# create-signing-cert.sh, Full Disk Access survives rebuilds (TCC keys on the certificate);
# otherwise ad-hoc, which ties the grant to this exact build.
SIGN_ID="${DISKWATCH_SIGN_ID:-Diskwatch Local Code Signing}"
if (( installed_build )) && security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$SIGN_ID\""; then
  sign=("$SIGN_ID"); echo "signing with \"$SIGN_ID\""
else
  sign=(-); echo "signing ad-hoc (run create-signing-cert.sh for rebuild-stable permissions)"
fi
codesign --force --sign "${sign[0]}" --identifier com.diskwatch.duc "$app/Contents/Resources/bin/duc"
codesign --force --sign "${sign[0]}" --identifier com.diskwatch.app "$app"
codesign --verify --strict --verbose=1 "$app"
for f in MacOS/diskwatch-launcher Resources/bin/duc; do
  printf '  %-28s %s, min macOS %s\n' "$f" "$(lipo -archs "$app/Contents/$f")" \
    "$(otool -l "$app/Contents/$f" | awk '/minos/{print $2; exit}')"
done
# Refresh Launch Services so Finder shows the icon.
touch "$app"
(( installed_build )) && /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
# Re-register the agent for the new build (also repairs one launchd can no longer start, and
# migrates a pre-1.1.1 LaunchAgent file to the com.diskwatch.tick label).
L="$app/Contents/MacOS/diskwatch-launcher"
if (( installed_build )) && [[ $("$L" --agent-status 2>/dev/null) =~ ^(enabled|broken|requires-approval)$ ]]; then
  "$L" --unregister >/dev/null; sleep 5
  echo "agent: $("$L" --register)"
fi
echo "built $app"
