#!/usr/bin/env bash
# setup-et-server.sh — build EternalTerminal (etserver) and its missing
# dependencies (libsodium, gflags) into $HOME/.local, then register a
# systemd user service that listens on 127.0.0.1:2022.
#
# Targets CBL-Mariner 2.0 where libsodium/gflags aren't packaged. Also
# works on any glibc Linux that already has cmake, gcc-c++, protobuf-devel,
# openssl-devel, ncurses-devel, and boost-devel.
#
# Idempotent — skips builds whose artefacts already exist; pass --force to
# rebuild everything.

set -euo pipefail

PREFIX="$HOME/.local"
SRC="$HOME/.local/src/et-build"
JOBS="$(nproc 2>/dev/null || echo 4)"
LIBSODIUM_VER=1.0.20
GFLAGS_VER=2.2.2
ET_TAG=et-v6.2.11
ET_PORT=2022

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
  esac
done

mkdir -p "$PREFIX/bin" "$PREFIX/lib" "$PREFIX/include" "$SRC"
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export CMAKE_PREFIX_PATH="$PREFIX:${CMAKE_PREFIX_PATH:-}"
export LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}"

need() { command -v "$1" >/dev/null || { echo "missing: $1" >&2; exit 1; }; }
need cmake; need make; need g++; need curl; need tar; need git

build_libsodium() {
  if [[ $FORCE -eq 0 && -f "$PREFIX/lib/libsodium.a" ]]; then
    echo ">> libsodium already built"
    return
  fi
  echo ">> building libsodium $LIBSODIUM_VER"
  cd "$SRC"
  curl -fsSL "https://download.libsodium.org/libsodium/releases/libsodium-$LIBSODIUM_VER.tar.gz" \
    | tar -xz
  cd "libsodium-$LIBSODIUM_VER"
  ./configure --prefix="$PREFIX" --disable-shared --enable-static --quiet
  make -j"$JOBS" >/dev/null
  make install >/dev/null
}

build_gflags() {
  if [[ $FORCE -eq 0 && -f "$PREFIX/lib/libgflags.a" ]]; then
    echo ">> gflags already built"
    return
  fi
  echo ">> building gflags $GFLAGS_VER"
  cd "$SRC"
  rm -rf gflags
  git clone --depth 1 --branch "v$GFLAGS_VER" https://github.com/gflags/gflags.git
  cd gflags
  cmake -S . -B build -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DGFLAGS_NAMESPACE=google >/dev/null
  cmake --build build -j"$JOBS" >/dev/null
  cmake --install build >/dev/null
}

build_et() {
  if [[ $FORCE -eq 0 && -x "$PREFIX/bin/etserver" ]]; then
    echo ">> etserver already built ($("$PREFIX/bin/etserver" --version 2>&1 | head -1))"
    return
  fi
  echo ">> building $ET_TAG"
  cd "$SRC"
  rm -rf EternalTerminal
  git clone --depth 1 --branch "$ET_TAG" --recursive \
    https://github.com/MisterTea/EternalTerminal.git
  cd EternalTerminal
  cmake -S . -B build -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DDISABLE_CRASH_LOG=ON >/dev/null
  cmake --build build -j"$JOBS" >/dev/null
  cmake --install build >/dev/null
  echo ">> installed: $($PREFIX/bin/etserver --version 2>&1 | head -1)"
}

write_service() {
  local unit="$HOME/.config/systemd/user/etserver.service"
  mkdir -p "$(dirname "$unit")"
  cat >"$unit" <<EOF
[Unit]
Description=EternalTerminal server (user, loopback only)
After=network.target

[Service]
Type=simple
ExecStart=$PREFIX/bin/etserver --port $ET_PORT --serverfifo %t/etserver.idpasskey.fifo
Restart=on-failure
RestartSec=2
Environment=LD_LIBRARY_PATH=$PREFIX/lib

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now etserver.service
  systemctl --user --no-pager status etserver.service | head -10 || true
}

build_libsodium
build_gflags
build_et
write_service

cat <<EOF

Done. etserver listening on 127.0.0.1:$ET_PORT.

On your Mac:
  brew install eternal-terminal

Append to ~/.ssh/config (replace VM_HOST with this VM's reachable name):
  Host devvm-et
      HostName VM_HOST
      User $USER
      ProxyCommand /opt/homebrew/bin/et --jumphost %h --jport $ET_PORT --tunnel %h:%p

Then in VS Code: Remote-SSH: Connect to Host... -> devvm-et

Verify the service after a reboot/relogin:
  systemctl --user status etserver
EOF
