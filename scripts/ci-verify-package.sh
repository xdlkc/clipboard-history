#!/bin/bash
# 验收第 6、7 项:校验 package.sh 的产物。
#   zip 解压后 codesign --verify --strict、lipo -info、Info.plist / 图标;
#   dmg 只读挂载,检查 app + 安装说明 + Applications 链接并校验签名;没有残留的中间 .app;
#   启动一次打包后的 app(临时数据库),确认是 UIElement(无 Dock 图标)。
# 只在 CI 中运行:会结束正在运行的 ClipboardHistory。
# 用法: scripts/ci-verify-package.sh <输出目录>
set -euo pipefail

if [ "${CI:-}" != "true" ]; then
  echo "拒绝运行:本脚本只用于 CI(需要 CI=true)。它会退出正在运行的 ClipboardHistory 并启动打包后的 app。" >&2
  exit 2
fi

cd "$(dirname "$0")/.."
OUT="${1:?usage: $0 <output dir>}"
mkdir -p "$OUT"
APP_NAME="ClipboardHistory"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Info.plist)"
NAME="$APP_NAME-$VERSION"
ZIP="dist/$NAME.zip"
DMG="dist/$NAME.dmg"
GUIDE="安装说明.txt"
WORK="$(mktemp -d)"
MOUNT=""
APP_PID=""

cleanup() {
  [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null || true
  if [ -n "$MOUNT" ]; then hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force -quiet || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
section() { echo; echo "---- $* ----"; }

section "dist"
ls -l dist
[ -f "$ZIP" ] || fail "缺少 $ZIP"
[ -f "$DMG" ] || fail "缺少 $DMG"
LEFT="$(find build dist -name '*.app' -prune 2>/dev/null || true)"
[ -z "$LEFT" ] || fail "残留中间 .app: $LEFT"
for d in dist/stage dist/dmgroot dist/verify; do [ ! -e "$d" ] || fail "残留中间目录 $d"; done
echo "no intermediate .app or staging dirs left"

section "zip: unzip + codesign --verify --strict"
ditto -x -k "$ZIP" "$WORK/zip"
APP="$WORK/zip/$NAME/$APP_NAME.app"
ls -la "$WORK/zip/$NAME"
[ -f "$WORK/zip/$NAME/$GUIDE" ] || fail "zip 内缺少 $GUIDE"
codesign --verify --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "^(Identifier|Format|Signature|CodeDirectory)"

section "lipo -info"
lipo -info "$APP/Contents/MacOS/$APP_NAME"
lipo "$APP/Contents/MacOS/$APP_NAME" -verify_arch arm64 x86_64

section "bundle"
plutil -lint "$APP/Contents/Info.plist"
for key in CFBundleIdentifier CFBundleShortVersionString LSUIElement CFBundleIconFile CFBundleDevelopmentRegion; do
  echo "$key = $(/usr/libexec/PlistBuddy -c "Print :$key" "$APP/Contents/Info.plist")"
done
[ "$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$APP/Contents/Info.plist")" = "true" ] || fail "LSUIElement 不是 true"
file "$APP/Contents/Resources/AppIcon.icns"
iconutil -c iconset "$APP/Contents/Resources/AppIcon.icns" -o "$WORK/check.iconset"
ls "$WORK/check.iconset"
[ "$(ls "$WORK/check.iconset" | wc -l | tr -d ' ')" = "10" ] || fail "AppIcon.icns 不是 10 个尺寸"

section "dmg: attach read-only"
MOUNT="$WORK/mnt"
mkdir -p "$MOUNT"
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT" -quiet
ls -la "$MOUNT"
[ -d "$MOUNT/$APP_NAME.app" ] || fail "dmg 内缺少 $APP_NAME.app"
[ -f "$MOUNT/$GUIDE" ] || fail "dmg 内缺少 $GUIDE"
[ "$(readlink "$MOUNT/Applications")" = "/Applications" ] || fail "dmg 内 Applications 不是指向 /Applications 的链接"
codesign --verify --strict --verbose=2 "$MOUNT/$APP_NAME.app"
hdiutil detach "$MOUNT" -quiet
MOUNT=""
echo "dmg detached"

section "launch packaged app (temp DB)"
pkill -x "$APP_NAME" 2>/dev/null || true   # 旧实例必须先退出(坑 7)
DB="$WORK/history.db"
open -n "$APP" --env "CLIPBOARD_HISTORY_DB=$DB"
for _ in $(seq 1 30); do
  APP_PID="$(pgrep -nx "$APP_NAME" || true)"
  [ -n "$APP_PID" ] && [ -f "$DB" ] && break
  sleep 0.3
done
[ -n "$APP_PID" ] || fail "打包后的 app 未启动"
[ -f "$DB" ] || fail "打包后的 app 未使用临时数据库"
sleep 1
kill -0 "$APP_PID" 2>/dev/null || fail "打包后的 app 启动后退出"
TYPE="$(lsappinfo info -only ApplicationType -app "$BUNDLE_ID" || true)"
echo "pid=$APP_PID $TYPE"
case "$TYPE" in *UIElement*) ;; *) fail "不是 UIElement(会出现 Dock 图标)" ;; esac
screencapture -x "$OUT/packaged-app-running.png" || true
kill "$APP_PID"
APP_PID=""
echo
echo "package verification passed"
