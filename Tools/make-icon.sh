#!/bin/bash
# 生成 Resources/AppIcon.icns
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONSET="$ROOT/build/AppIcon.iconset"

rm -rf "$ICONSET"
mkdir -p "$ROOT/build"

swift "$ROOT/Tools/make-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"

echo "==> 完成: Resources/AppIcon.icns"
