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
  run)
    odin run src -out:asgard -debug
    ;;
  *)
    echo "usage: $0 [debug|release|run]"
    exit 1
    ;;
esac
