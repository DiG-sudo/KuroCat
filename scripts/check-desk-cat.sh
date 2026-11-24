#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -g -module-cache-path "$CHECK_DIR/cache" "$ROOT/Sources/KeyMap.swift" "$ROOT/Sources/InputEngine.swift" "$ROOT/Sources/CatPhysics.swift" "$ROOT/Sources/CoatPatterns.swift" "$ROOT/Sources/CatRenderer.swift" "$ROOT/tests/desk/main.swift" -o "$CHECK_DIR/check" -framework AppKit -framework CoreGraphics -framework QuartzCore -framework IOKit -framework ApplicationServices
KUROCAT_ARTWORK_DIR="$ROOT/Resources/CustomCat" "$CHECK_DIR/check" "${1:-$ROOT/assets/desk-cat-v1/preview}"
