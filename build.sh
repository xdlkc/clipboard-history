#!/bin/bash
# 本机构建:两架构分别 release 构建 → lipo → 组装 build/ClipboardHistory.app → 代码签名。
#
# 签名身份:
#   默认使用钥匙串中名为 $SIGN_IDENTITY(默认 "ClipboardHistory Self-Signed")的有效代码签名证书,
#   找不到时退回 ad-hoc 并提示;SIGN=adhoc 强制 ad-hoc(分发包与 CI 一律 ad-hoc)。
#   证书签名后替换 /Applications 里的副本,辅助功能授权仍然有效;ad-hoc 签名每次重编都需重新授权。
# 其他环境变量:
#   SWIFT_BUILD_FLAGS  追加给 swift build 的参数,如 "-Xswiftc -warnings-as-errors"
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ClipboardHistory"
APP="build/$APP_NAME.app"
SIGN_IDENTITY="${SIGN_IDENTITY:-ClipboardHistory Self-Signed}"
read -r -a EXTRA_FLAGS <<<"${SWIFT_BUILD_FLAGS:-}"

log() { echo "==> $*"; }

# 坑 3:两架构分别构建,产物在 .build/<triple>/release/,不依赖 .build/release 软链
for arch in arm64 x86_64; do
  log "swift build -c release --arch $arch"
  swift build -c release --arch "$arch" ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"}
done
ARM_BIN="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"
X86_BIN="$(swift build -c release --arch x86_64 --show-bin-path)/$APP_NAME"

log "icon: assets/icon-1024.png → build/AppIcon.icns"
mkdir -p build
if [ ! -x build/make-icon ] || [ make-icon.swift -nt build/make-icon ]; then
  swiftc -O make-icon.swift -o build/make-icon
fi
build/make-icon assets/icon-1024.png build/AppIcon.icns build/AppIcon.iconset

log "assemble $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$ARM_BIN" "$X86_BIN" -output "$APP/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
lipo -info "$APP/Contents/MacOS/$APP_NAME"

# 坑 6:有证书用证书,SIGN=adhoc 或找不到证书时 ad-hoc
if [ "${SIGN:-}" = "adhoc" ]; then
  IDENTITY="-"
  log "codesign: ad-hoc (SIGN=adhoc)"
elif security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$SIGN_IDENTITY\""; then
  IDENTITY="$SIGN_IDENTITY"
  log "codesign: \"$SIGN_IDENTITY\""
else
  IDENTITY="-"
  log "codesign: 未找到有效证书 \"$SIGN_IDENTITY\",退回 ad-hoc(替换 /Applications 副本后需重新授权辅助功能,见 README)"
fi
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "^(Identifier|Format|Signature|Authority|TeamIdentifier)=" || true
log "done: $APP"
