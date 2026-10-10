#!/bin/bash
# 分发打包:SIGN=adhoc ./build.sh → dist/ClipboardHistory-<版本>.zip 与 .dmg(app + 《安装说明.txt》)。
# 分发包强制 ad-hoc 签名。结束时(包括失败时)删除全部中间 .app 与目录,只留下 zip 和 dmg(坑 8)。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ClipboardHistory"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)"
NAME="$APP_NAME-$VERSION"
DIST="dist"
STAGE="$DIST/stage"
DMGROOT="$DIST/dmgroot"
VERIFY="$DIST/verify"
ZIP="$DIST/$NAME.zip"
DMG="$DIST/$NAME.dmg"
GUIDE="安装说明.txt"
MOUNT=""

log() { echo "==> $*"; }

cleanup() {
  if [ -n "$MOUNT" ]; then hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force -quiet || true; fi
  rm -rf "$STAGE" "$DMGROOT" "$VERIFY" build/*.app
}
trap cleanup EXIT

log "package $NAME"
SIGN=adhoc ./build.sh

rm -rf "$STAGE" "$DMGROOT" "$VERIFY" "$ZIP" "$DMG"
mkdir -p "$STAGE/$NAME" "$DMGROOT" "$VERIFY"
sed "s/{{VERSION}}/$VERSION/g" "packaging/$GUIDE" > "$STAGE/$NAME/$GUIDE"
ditto "build/$APP_NAME.app" "$STAGE/$NAME/$APP_NAME.app"

log "zip → $ZIP"
ditto -c -k --keepParent "$STAGE/$NAME" "$ZIP"

log "dmg → $DMG"
ditto "build/$APP_NAME.app" "$DMGROOT/$APP_NAME.app"
cp "$STAGE/$NAME/$GUIDE" "$DMGROOT/$GUIDE"
ln -s /Applications "$DMGROOT/Applications"
# 运行器上 hdiutil 偶尔报 "Resource busy",重试几次
for attempt in 1 2 3; do
  if hdiutil create -volname "$NAME" -srcfolder "$DMGROOT" -format UDZO -ov "$DMG"; then break; fi
  [ "$attempt" = 3 ] && exit 1
  sleep 3
done

log "verify zip"
ditto -x -k "$ZIP" "$VERIFY/zip"
codesign --verify --strict --verbose=2 "$VERIFY/zip/$NAME/$APP_NAME.app"

log "verify dmg"
MOUNT="$(mktemp -d /tmp/clipboard-history-dmg.XXXXXX)"
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT" -quiet
[ -L "$MOUNT/Applications" ] && [ -f "$MOUNT/$GUIDE" ] || { echo "dmg 内容不完整" >&2; exit 1; }
codesign --verify --strict --verbose=2 "$MOUNT/$APP_NAME.app"
hdiutil detach "$MOUNT" -quiet
rmdir "$MOUNT" 2>/dev/null || true
MOUNT=""

cleanup
trap - EXIT
LEFT="$(find build dist -name '*.app' -prune 2>/dev/null || true)"
[ -z "$LEFT" ] || { echo "残留中间 .app: $LEFT" >&2; exit 1; }
ls -l "$ZIP" "$DMG"
log "done"
