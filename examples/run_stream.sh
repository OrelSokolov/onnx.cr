#!/usr/bin/env bash
# Build the miniaudio bridge (if needed) and run the streaming example.
#
#   ./examples/run_stream.sh "Привет!"
#   PIPER_MODEL=/path/to/voice.onnx ./examples/run_stream.sh "text"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

eval "$("$ROOT/ext/miniaudio/build.sh")"

exec crystal run "$ROOT/examples/piper_stream.cr" --link-flags "$MA_LINK_FLAGS" -- "$@"
