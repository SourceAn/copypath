#!/bin/bash
# 卸载 CopyPath：注销扩展、删除 App。
set -euo pipefail

DEST="/Applications/CopyPath.app"
APPEX_ID="com.mroeidea.copypath.finder"
APPEX="$DEST/Contents/PlugIns/CopyPathFinder.appex"
AGENT_PLIST="$HOME/Library/LaunchAgents/com.mroeidea.copypath.agent.plist"

echo "==> 移除开机自启"
rm -f "$AGENT_PLIST"
launchctl bootout "gui/$(id -u)/com.mroeidea.copypath.agent" 2>/dev/null || true

echo "==> 停用扩展"
pluginkit -e ignore -i "$APPEX_ID" 2>/dev/null || true

if [ -d "$APPEX" ]; then
    pluginkit -r "$APPEX" 2>/dev/null || true
fi

echo "==> 退出进程"
pkill -f "$DEST/Contents/MacOS/CopyPath" 2>/dev/null || true
pkill -f "$DEST/Contents/PlugIns/CopyPathFinder.appex" 2>/dev/null || true

echo "==> 删除 $DEST"
rm -rf "$DEST"

echo "==> 重启 Finder"
killall Finder 2>/dev/null || true

echo "==> 已卸载"
