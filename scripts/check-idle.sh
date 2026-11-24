#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -O "$ROOT/Sources/KeyMap.swift" "$ROOT/Sources/InputEngine.swift" "$ROOT/Sources/CatPhysics.swift" "$ROOT/Sources/CoatPatterns.swift" "$ROOT/Sources/CatRenderer.swift" "$ROOT/tests/idle/main.swift" -o "$CHECK_DIR/check" -framework AppKit -framework CoreGraphics -framework QuartzCore -framework IOKit -framework ApplicationServices
KUROCAT_ARTWORK_DIR="$ROOT/Resources/CustomCat" "$CHECK_DIR/check" "$ROOT" "${1:-$ROOT/assets/idle-actions-v9/integration}"
