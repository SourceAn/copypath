#!/bin/bash
# 构建 CopyPath.app（主程序 + Finder 同步扩展），不需要 Xcode。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT/build"
SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macos13.0"

APP_NAME="CopyPath"
APPEX_NAME="CopyPathFinder"

APP="$BUILD_DIR/$APP_NAME.app"
APPEX="$APP/Contents/PlugIns/$APPEX_NAME.appex"

echo "==> 清理 $BUILD_DIR"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" \
         "$APP/Contents/Resources" \
         "$APPEX/Contents/MacOS" \
         "$APPEX/Contents/Resources"

echo "==> 编译 Finder 扩展"
xcrun swiftc \
    -O \
    -target "$TARGET" -sdk "$SDK" \
    -module-name "$APPEX_NAME" \
    -application-extension \
    -parse-as-library \
    -framework Cocoa -framework FinderSync -framework UserNotifications \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$APPEX/Contents/MacOS/$APPEX_NAME" \
    "$ROOT/Sources/FinderExt/CopyPathFinderSync.swift"

echo "==> 编译主程序"
xcrun swiftc \
    -O \
    -target "$TARGET" -sdk "$SDK" \
    -module-name "$APP_NAME" \
    ${SWIFT_FLAGS:-} \
    -framework Cocoa -framework FinderSync \
    -o "$APP/Contents/MacOS/$APP_NAME" \
    "$ROOT/Sources/App/main.swift" \
    "$ROOT/Sources/App/AppDelegate.swift" \
    "$ROOT/Sources/App/LoginItem.swift"

echo "==> 写入 Info.plist"
cp "$ROOT/Resources/App-Info.plist"       "$APP/Contents/Info.plist"
cp "$ROOT/Resources/FinderExt-Info.plist" "$APPEX/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> ad-hoc 签名"
codesign --force --sign - \
    --entitlements "$ROOT/Resources/FinderExt.entitlements" \
    "$APPEX"
codesign --force --sign - "$APP"

echo "==> 校验"
codesign --verify --deep --strict --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

# build/ 里的副本和 /Applications 里的 bundle ID 相同，同时注册会让 LaunchServices
# 分不清该用哪份（通知横幅的图标会解析失败）。构建完就把它从 LaunchServices 注销掉。
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$APP" 2>/dev/null || true

echo "==> 完成: $APP"
