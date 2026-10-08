#!/usr/bin/env bash
# Build a standalone, universal (arm64 + x86_64) duc for Diskwatch.app, runnable on
# macOS 12 Monterey and later: vim keys (duc_vim_patch.py), indexing + ncurses UI,
# Tokyo Cabinet built from source and linked statically; otherwise only macOS system
# libraries (/usr/lib). Build-time needs: Xcode command line tools, curl, python3
# (no Homebrew: Tokyo Cabinet is passed via TC_CFLAGS/TC_LIBS, pkg-config is not used).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export MACOSX_DEPLOYMENT_TARGET=12.0
archs=(arm64 x86_64)

TC_VER=1.4.48
TC_URL="https://dbmx.net/tokyocabinet/tokyocabinet-$TC_VER.tar.gz"
TC_SHA=a003f47c39a91e22d76bc4fe68b9b3de0f38851b160bbb1ca07a4f6441de1f90
DUC_VER=1.4.6
DUC_URL="https://github.com/zevv/duc/releases/download/$DUC_VER/duc-$DUC_VER.tar.gz"
DUC_SHA=e91592e367f3f8be671899660756b25e2c37f316c42ebd2a36dd684be3e2f25a

out="$here/build"; mkdir -p "$out"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
fetch() { # url sha dest
  curl -fsSL "$1" -o "$3"
  echo "$2  $3" | shasum -a 256 -c --quiet - || { echo "checksum mismatch: $1" >&2; exit 1; }
}
fetch "$TC_URL" "$TC_SHA" "$work/tc.tar.gz"
fetch "$DUC_URL" "$DUC_SHA" "$work/duc.tar.gz"
sdk=$(xcrun --show-sdk-path)

for arch in "${archs[@]}"; do
  echo "== $arch"
  host=$([[ $arch == arm64 ]] && echo aarch64-apple-darwin || echo x86_64-apple-darwin)
  cc="clang -arch $arch -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -isysroot $sdk"
  pfx="$work/prefix-$arch"

  # Tokyo Cabinet: static library only.
  mkdir -p "$work/tc-$arch" && tar xzf "$work/tc.tar.gz" -C "$work/tc-$arch" --strip-components 1
  (cd "$work/tc-$arch" && ./configure -q --host="$host" --prefix="$pfx" CC="$cc" CFLAGS="-O2" >/dev/null \
     && make -s -j"$(sysctl -n hw.ncpu)" libtokyocabinet.a >/dev/null 2>&1 \
     && mkdir -p "$pfx/lib" "$pfx/include" && cp libtokyocabinet.a "$pfx/lib/" \
     && cp tcutil.h tchdb.h tcbdb.h tcfdb.h tctdb.h tcadb.h "$pfx/include/")

  # duc against that archive, system ncurses/zlib/bz2.
  mkdir -p "$work/duc-$arch" && tar xzf "$work/duc.tar.gz" -C "$work/duc-$arch" --strip-components 1
  python3 "$here/../../common/duc_vim_patch.py" "$work/duc-$arch/src/duc/cmd-ui.c" --macos >/dev/null
  (cd "$work/duc-$arch" && ./configure -q --host="$host" --with-db-backend=tokyocabinet \
     --disable-cairo --disable-x11 --disable-opengl \
     CC="$cc" CPPFLAGS="-I$pfx/include" LDFLAGS="-L$pfx/lib" LIBS="-lz -lbz2 -lm" \
     TC_CFLAGS="-I$pfx/include" TC_LIBS="-L$pfx/lib -ltokyocabinet -lz -lbz2 -lm" \
     PKG_CONFIG=/usr/bin/false >/dev/null \
   && make -s -j"$(sysctl -n hw.ncpu)" 2>&1 | grep -iE '\berror\b' || true)
  cp "$work/duc-$arch/duc" "$work/duc.$arch"
done

lipo -create -output "$out/duc" "$work"/duc.*
chmod 755 "$out/duc"
echo "built $out/duc: $(lipo -archs "$out/duc"), minimum macOS $(otool -l "$out/duc" | awk '/minos/{print $2; exit}')"
otool -L "$out/duc" | tail -n +2
