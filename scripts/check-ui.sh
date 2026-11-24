#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -g "$ROOT/Sources/KeyMap.swift" "$ROOT/Sources/InputEngine.swift" "$ROOT/Sources/CatPhysics.swift" "$ROOT/Sources/CoatPatterns.swift" "$ROOT/Sources/CatRenderer.swift" "$ROOT/Sources/OverlayWindow.swift" "$ROOT/Sources/AppDelegate.swift" "$ROOT/tests/ui/main.swift" -o "$CHECK_DIR/check" -framework AppKit -framework CoreGraphics -framework QuartzCore -framework IOKit -framework ApplicationServices
OUT="$ROOT/assets/ui-interaction-v5"
if [ "$#" -gt 0 ]; then OUT="$1"; fi
KUROCAT_ARTWORK_DIR="$ROOT/Resources/CustomCat" "$CHECK_DIR/check" "$OUT"
