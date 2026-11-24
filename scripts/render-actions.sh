#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
swiftc -O "$ROOT/Sources/KeyMap.swift" "$ROOT/Sources/InputEngine.swift" "$ROOT/Sources/CatPhysics.swift" "$ROOT/Sources/CoatPatterns.swift" "$ROOT/Sources/CatRenderer.swift" "$ROOT/scripts/action-gallery/main.swift" -o "$BUILD_DIR/action-gallery" -framework AppKit -framework CoreGraphics -framework QuartzCore -framework IOKit -framework ApplicationServices
KUROCAT_ARTWORK_DIR="$ROOT/Resources/CustomCat" "$BUILD_DIR/action-gallery" "$ROOT/assets/actions"
