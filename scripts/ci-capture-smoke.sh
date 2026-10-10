#!/bin/bash
# 验收第 2 项:启动应用,通过真实系统剪贴板放入文本 / PNG / 文件 URL,检查 history.db 中的记录。
# 用法: scripts/ci-capture-smoke.sh <ClipboardHistory 可执行文件>
# 只在 CI 中运行:脚本会结束正在运行的 ClipboardHistory 并改动系统剪贴板。数据库始终是 mktemp 下的临时库。
set -euo pipefail

if [ "${CI:-}" != "true" ]; then
  echo "拒绝运行:本脚本只用于 CI(需要 CI=true)。它会退出正在运行的 ClipboardHistory 并覆盖系统剪贴板。" >&2
  exit 2
fi

BIN="${1:?usage: $0 <ClipboardHistory binary>}"
WORK="$(mktemp -d)"
DB="$WORK/history.db"
LOG="$WORK/app.log"
APP_PID=""

cleanup() {
  [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  echo "--- app log ---" >&2
  cat "$LOG" >&2 || true
  echo "--- items ---" >&2
  sqlite3 "$DB" "SELECT id, kind, text, length(image), length(thumb), app FROM items" >&2 || true
  exit 1
}

# 旧实例必须先退出(坑 7)
pkill -x ClipboardHistory 2>/dev/null || true

CLIPBOARD_HISTORY_DB="$DB" "$BIN" >"$LOG" 2>&1 &
APP_PID=$!

for _ in $(seq 1 50); do
  [ -f "$DB" ] && break
  sleep 0.2
done
[ -f "$DB" ] || fail "history.db 未创建"
kill -0 "$APP_PID" 2>/dev/null || fail "进程已退出"
grep -qF "store=$DB " "$LOG" || fail "app 未使用临时数据库 $DB"

# 等待 kind 为 $1 且满足条件 $2 的记录出现
wait_row() {
  local kind="$1" cond="$2" n=""
  for _ in $(seq 1 25); do
    n="$(sqlite3 "$DB" "SELECT COUNT(*) FROM items WHERE kind=$kind AND $cond" 2>/dev/null || echo 0)"
    [ "${n:-0}" -ge 1 ] && return 0
    sleep 0.2
  done
  return 1
}

TOKEN="smoke-$RANDOM-$RANDOM"
printf 'line1 %s\n\tline2' "$TOKEN" | pbcopy
wait_row 0 "text LIKE '%$TOKEN%' AND image IS NULL" || fail "pbcopy 文本未记录为 kind=0"
echo "OK text: $(sqlite3 "$DB" "SELECT 'kind='||kind||' app='||IFNULL(app,'-') FROM items WHERE kind=0 LIMIT 1")"

PNG="$WORK/smoke.png"
osascript -l JavaScript -e "
ObjC.import('AppKit');
var rep = \$.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(null, 120, 80, 8, 4, true, false, 'NSDeviceRGBColorSpace', 0, 0);
rep.representationUsingTypeProperties(\$.NSBitmapImageFileTypePNG, \$()).writeToFileAtomically('$PNG', true);
" >/dev/null
[ -s "$PNG" ] || fail "无法生成测试 PNG"

osascript -e "set the clipboard to (read (POSIX file \"$PNG\") as «class PNGf»)"
wait_row 1 "text = '120×80' AND length(image) > 0 AND length(thumb) > 0" || fail "PNG 未记录为 kind=1 + 缩略图"
echo "OK image: $(sqlite3 "$DB" "SELECT 'kind='||kind||' text='||text||' image='||length(image)||'B thumb='||length(thumb)||'B' FROM items WHERE kind=1 LIMIT 1")"

osascript -l JavaScript -e "
ObjC.import('AppKit');
var pb = \$.NSPasteboard.generalPasteboard;
pb.clearContents;
pb.writeObjects(\$([\$.NSURL.fileURLWithPath('$PNG')]));
" >/dev/null
wait_row 2 "text = '$PNG' AND length(thumb) > 0" || fail "文件 URL 未记录为 kind=2 + 首图缩略图"
echo "OK file: $(sqlite3 "$DB" "SELECT 'kind='||kind||' text='||text||' thumb='||length(thumb)||'B' FROM items WHERE kind=2 LIMIT 1")"

kill -0 "$APP_PID" 2>/dev/null || fail "进程已退出"
echo "--- app log ---"
cat "$LOG"
echo "capture smoke passed"
