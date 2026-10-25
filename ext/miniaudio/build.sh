#!/usr/bin/env bash
# Build the miniaudio streaming bridge (vendor of the single-header lib in
# ext/miniaudio/) and print the Crystal link flags on the last line.
#
#   eval "$(ext/miniaudio/build.sh)"
#
# Mirrors h2code's scripts/build_miniaudio.sh: Unix cc builds on Linux/macOS,
# MSVC via Git-for-Windows bash on Windows (with a MinGW fallback). The
# miniaudio implementation TU is compiled once and cached; stream_bridge.c
# is rebuilt every run.
#
# Honors $CC and $CFLAGS (default -O2).

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC="${CC:-cc}"
CFLAGS="${CFLAGS:--O2}"

# Convert a POSIX path to Windows form for native MSVC tools (see
# h2code/scripts/build_miniaudio.sh for the MSYS argument-conversion rationale).
wpath() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s' "$1"
  fi
}

target="${1:-}"
if [ -z "$target" ]; then
  case "$(uname -s)" in
    Darwin)               target="x86_64-darwin" ;;
    Linux)                target="x86_64-linux" ;;
    MINGW*|MSYS*|CYGWIN*) target="x86_64-windows" ;;
  esac
fi

# Locate an MSVC cl.exe (Crystal's native Windows toolchain — a MinGW bridge
# object mixes C runtimes with it and fails the link). Same probe as h2code.
find_msvc_cl() {
  for name in cl cl.exe; do
    if command -v "$name" >/dev/null 2>&1; then
      command -v "$name"
      return 0
    fi
  done

  local vswhere=""
  for p in \
    "/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe" \
    "/c/Program Files/Microsoft Visual Studio/Installer/vswhere.exe"
  do
    if [ -x "$p" ]; then
      vswhere="$p"
      break
    fi
  done
  [ -n "$vswhere" ] || return 1

  local install_path
  install_path=$("$vswhere" -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>/dev/null | head -n1 | tr -d '\r')
  [ -n "$install_path" ] || return 1

  local posix_path
  if command -v cygpath >/dev/null 2>&1; then
    posix_path=$(cygpath -u "$install_path")
  else
    posix_path=$(echo "$install_path" | sed 's|\\|/|g; s|^\([A-Za-z]\):|/\L\1|')
  fi

  local cl_exe
  cl_exe=$(ls -d "$posix_path/VC/Tools/MSVC"/*/bin/Hostx64/x64/cl.exe 2>/dev/null | sort -V | tail -n1)
  [ -n "$cl_exe" ] && [ -x "$cl_exe" ] || return 1
  echo "$cl_exe"
}

# One-time compile of the miniaudio implementation TU (slow, ~1 min).
ensure_impl() {
  if [ ! -f "$DIR/miniaudio_impl.o" ]; then
    printf '#define MINIAUDIO_IMPLEMENTATION\n#include "miniaudio.h"\n' > "$DIR/miniaudio_impl.c"
    "$CC" -c $CFLAGS -I"$DIR" "$DIR/miniaudio_impl.c" -o "$DIR/miniaudio_impl.o"
  fi
}

build_unix() {
  ensure_impl
  "$CC" -c $CFLAGS -I"$DIR" "$DIR/stream_bridge.c" -o "$DIR/stream_bridge.o"
  ar rcs "$DIR/libstream_bridge.a" "$DIR/miniaudio_impl.o" "$DIR/stream_bridge.o"
}

build_windows_msvc() {
  local cl_exe="$1"
  local impl_obj="$DIR/miniaudio_impl.obj"
  local bridge_obj="$DIR/stream_bridge.obj"
  # Drop stale Unix artifacts so packaging cannot pick up the wrong object.
  rm -f "$DIR"/*.o "$DIR"/libstream_bridge.a "$impl_obj" "$bridge_obj"
  if [ ! -f "$impl_obj" ]; then
    printf '#define MINIAUDIO_IMPLEMENTATION\n#include "miniaudio.h"\n' > "$DIR/miniaudio_impl.c"
    # cl.exe reports errors on stdout; mirror chatter to stderr (see h2code).
    "$cl_exe" -nologo -O2 -c -I"$(wpath "$DIR")" "$(wpath "$DIR/miniaudio_impl.c")" -Fo"$(wpath "$impl_obj")" 1>&2
  fi
  "$cl_exe" -nologo -O2 -c -I"$(wpath "$DIR")" "$(wpath "$DIR/stream_bridge.c")" -Fo"$(wpath "$bridge_obj")" 1>&2
  echo "$(wpath "$impl_obj") $(wpath "$bridge_obj") winmm.lib ole32.lib ksuser.lib"
}

build_windows_mingw() {
  build_unix
  echo "-L$DIR -lstream_bridge winmm.lib ole32.lib ksuser.lib"
}

case "$target" in
  *-darwin*)
    build_unix
    # CoreAudio backend — frameworks only, dlopens nothing.
    echo "-L$DIR -lstream_bridge -framework CoreAudio -framework AudioToolbox -framework CoreFoundation" ;;
  *-windows*|*-win32*|*-mingw*)
    cl_exe=$(find_msvc_cl || true)
    if [ -n "$cl_exe" ]; then
      build_windows_msvc "$cl_exe"
    else
      build_windows_mingw
    fi ;;
  *)
    build_unix
    # Linux: PulseAudio/ALSA are dlopened by miniaudio at runtime.
    echo "-L$DIR -lstream_bridge -ldl -lpthread -lm" ;;
esac
