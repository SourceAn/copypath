#!/bin/bash
# 构建 + 安装到 /Applications + 注册 Finder 扩展 + 设置开机自启。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="CopyPath"
APPEX_NAME="CopyPathFinder"
APPEX_ID="com.mroeidea.copypath.finder"
AGENT_LABEL="com.mroeidea.copypath.agent"
DEST="/Applications/$APP_NAME.app"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"

"$ROOT/build.sh"

echo "==> 退出旧实例"
pkill -f "$DEST/Contents/MacOS/$APP_NAME" 2>/dev/null || true

echo "==> 安装到 $DEST"
rm -rf "$DEST"
cp -R "$ROOT/build/$APP_NAME.app" "$DEST"

echo "==> 刷新 LaunchServices 缓存（图标）"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$DEST"

echo "==> 注册扩展"
pluginkit -a "$DEST/Contents/PlugIns/$APPEX_NAME.appex" || true
pluginkit -e use -i "$APPEX_ID" || true

echo "==> 安装开机自启"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$AGENT_LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$DEST/Contents/MacOS/$APP_NAME</string>
		<string>--background</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
PLIST

echo "==> 重启 Finder"
killall Finder 2>/dev/null || true

echo "==> 启动 App（弹出设置窗口）"
open "$DEST"

sleep 2
echo "==> pluginkit 状态"
pluginkit -m -p com.apple.FinderSync -v 2>&1 | grep -i copypath || echo "  ⚠️  未在 pluginkit 中找到扩展"
echo "==> 开机自启"
[ -f "$AGENT_PLIST" ] && echo "  已写入 $AGENT_PLIST" || echo "  ⚠️  未写入"
