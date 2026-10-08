#!/usr/bin/env bash
# Build duc-ui (duc's ncurses browser with vim keys and the `i` info popup) for Debian
# releases in throwaway Docker containers. Each build uses the duc version that release
# ships as an apt package, so the index format matches the system `duc`.
#
#   linux/build-duc-ui.sh                    amd64, bookworm + trixie
#   ARCHES="amd64 arm64" linux/build-duc-ui.sh
#   DOCKER_HOST=ssh://user@builder linux/build-duc-ui.sh    build on a remote Docker host
#
# Output: linux/ansible/roles/diskwatch/files/duc-ui-<release>[-<arch>] (the Ansible role
# picks up duc-ui-<release> for the host's Debian release) and dist/.
# Needs: docker (Desktop, OrbStack, colima, or a remote host via DOCKER_HOST).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
patch="$here/../common/duc_vim_patch.py"
role_files="$here/ansible/roles/diskwatch/files"
dist="$here/../dist"
builds=${BUILDS:-"bookworm:1.4.4 trixie:1.4.5"}   # release:duc version (apt-cache policy duc)
arches=${ARCHES:-amd64}
mkdir -p "$role_files" "$dist"

build_script='set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq build-essential pkg-config libncurses-dev libtokyocabinet-dev \
  python3 curl ca-certificates >/dev/null
cd /tmp && curl -fsSL "https://github.com/zevv/duc/releases/download/$DUC/duc-$DUC.tar.gz" | tar xz
cd "duc-$DUC" && python3 /tmp/duc_vim_patch.py src/duc/cmd-ui.c
./configure -q --with-db-backend=tokyocabinet --disable-cairo --disable-x11 --disable-opengl
make -s -j"$(nproc)" 2>&1 | grep -i error || true
mkdir -p /out && install -m 755 duc /out/duc-ui && ./duc --version | head -1'

for b in $builds; do
  rel=${b%%:*} ver=${b#*:}
  for arch in $arches; do
    echo "== $rel / $arch (duc $ver)"
    cid=$(docker create --platform "linux/$arch" -e DUC="$ver" "debian:$rel" bash -c "$build_script")
    trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
    docker cp "$patch" "$cid:/tmp/duc_vim_patch.py"
    docker start -a "$cid"
    out="duc-ui-$rel"; [[ $arch == amd64 ]] || out="$out-$arch"
    docker cp "$cid:/out/duc-ui" "$dist/$out-$arch.tmp"
    docker rm -f "$cid" >/dev/null; trap - EXIT
    mv "$dist/$out-$arch.tmp" "$dist/duc-ui-$rel-$arch"
    [[ $arch == amd64 ]] && cp "$dist/duc-ui-$rel-$arch" "$role_files/duc-ui-$rel"
  done
done
ls -la "$dist"/duc-ui-*
