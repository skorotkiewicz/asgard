#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"

case "$MODE" in
  debug)
    odin build src -out:asgard -debug
    ;;
  release)
    odin build src -out:asgard -o:speed -no-bounds-check
    ;;
  wasm)
    mkdir -p web
    cp "$(odin root)/core/sys/wasm/js/odin.js" web/odin.js
    odin build src -target:js_wasm32 -out:web/asgard.wasm -o:speed -no-bounds-check
    ;;
  run)
    odin run src -out:asgard -debug
    ;;
  *)
    echo "usage: $0 [debug|release|wasm|run]"
    exit 1
    ;;
esac
