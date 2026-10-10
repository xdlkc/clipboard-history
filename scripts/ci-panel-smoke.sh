#!/bin/bash
# 主面板冒烟测试(验收第 3 项窗口几何、第 4 项多行文本搜索不崩、第 5 项方向键跨类型切换不崩)。
# 用法: scripts/ci-panel-smoke.sh <ClipboardHistory 可执行文件> <输出目录>
# 只在 CI 中运行:会结束正在运行的 ClipboardHistory 并发送键盘事件。数据库始终是 mktemp 下的临时库。
set -euo pipefail

if [ "${CI:-}" != "true" ]; then
  echo "拒绝运行:本脚本只用于 CI(需要 CI=true)。它会退出正在运行的 ClipboardHistory 并模拟键盘输入。" >&2
  exit 2
fi

BIN="${1:?usage: $0 <ClipboardHistory binary> <output dir>}"
OUT="${2:?usage: $0 <ClipboardHistory binary> <output dir>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
DB="$WORK/history.db"
LOG="$OUT/panel-app.log"
HELPER="$WORK/ci-ui-helper"
APP_PID=""
mkdir -p "$OUT"

cleanup() {
  [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  echo "--- app log ---" >&2
  cat "$LOG" >&2 || true
  exit 1
}

alive() { kill -0 "$APP_PID" 2>/dev/null || fail "进程已退出(崩溃?)"; }

# 等待日志中出现匹配 $1 的行
wait_log() {
  for _ in $(seq 1 30); do
    grep -qE "$1" "$LOG" && return 0
    sleep 0.2
  done
  return 1
}

swiftc -O -o "$HELPER" "$SCRIPT_DIR/ci-ui-helper.swift"
echo "helper accessibility trusted: $("$HELPER" trusted)"

# ---- 准备测试数据(临时库) ----
PNG="$WORK/build-status.png"
osascript -l JavaScript -e "
ObjC.import('AppKit');
var rep = \$.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(null, 320, 200, 8, 4, true, false, 'NSDeviceRGBColorSpace', 0, 0);
var ctx = \$.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep);
\$.NSGraphicsContext.setCurrentContext(ctx);
\$.NSColor.colorWithSRGBRedGreenBlueAlpha(0.1, 0.5, 0.9, 1).setFill;
\$.NSRectFill(\$.NSMakeRect(0, 0, 320, 200));
\$.NSColor.colorWithSRGBRedGreenBlueAlpha(0.2, 0.8, 0.3, 1).setFill;
\$.NSRectFill(\$.NSMakeRect(20, 140, 280, 30));
\$.NSGraphicsContext.setCurrentContext(null);
rep.representationUsingTypeProperties(\$.NSBitmapImageFileTypePNG, \$()).writeToFileAtomically('$PNG', true);
" >/dev/null
[ -s "$PNG" ] || fail "无法生成测试 PNG"

NOW="$(date +%s)"
sqlite3 "$DB" <<SQL
CREATE TABLE items (
  id INTEGER PRIMARY KEY AUTOINCREMENT, kind INTEGER NOT NULL, text TEXT NOT NULL, image BLOB, thumb BLOB,
  app TEXT, created_at REAL NOT NULL, pinned INTEGER NOT NULL DEFAULT 0, content_hash TEXT NOT NULL UNIQUE);
INSERT INTO items (kind, text, app, created_at, pinned, content_hash) VALUES
 (0, '\$ swift build -c release --arch arm64' || char(13,10) || 'Building for production...' || char(13,10) ||
     '[1/9] Compiling ClipboardHistory Fuzzy.swift' || char(10) || char(9) ||
     'warning: ''NSBitmapImageRep(contentsOfFile:)'' is unavailable 🚨' || char(10) ||
     '中文输出 👨‍👩‍👧‍👦 Build complete! (14.82s)' || char(10),
  'com.apple.Terminal', $NOW - 120, 0, 'h-terminal'),
 (0, './build.sh && open build/ClipboardHistory.app', 'com.apple.Terminal', $NOW - 900, 1, 'h-pinned'),
 (0, 'Build failed: NSRange out of bounds' || char(10) || 'at RowView.swift:88', 'com.tinyspeck.slackmacgap', $NOW - 3600, 0, 'h-slack'),
 (0, 'github.com/xdlkc/clipboard-history/actions/workflows/build.yml', 'com.apple.Safari', $NOW - 90000, 0, 'h-url'),
 (0, 'BUILD_NUMBER=42 SIGN=adhoc ./package.sh', 'com.apple.Terminal', $NOW - 260000, 0, 'h-env');
INSERT INTO items (kind, text, image, thumb, app, created_at, pinned, content_hash) VALUES
 (1, '320×200', readfile('$PNG'), readfile('$PNG'), 'com.apple.Preview', $NOW - 1800, 0, 'h-image'),
 (2, '$PNG', NULL, readfile('$PNG'), 'com.apple.finder', $NOW - 2280, 0, 'h-file');
SQL
TOTAL="$(sqlite3 "$DB" "SELECT COUNT(*) FROM items")"
echo "seeded $TOTAL items"

# ---- 启动 ----
pkill -x ClipboardHistory 2>/dev/null || true   # 旧实例必须先退出(坑 7)
CLIPBOARD_HISTORY_DB="$DB" "$BIN" --show >"$LOG" 2>&1 &
APP_PID=$!
wait_log "panel show" || fail "面板未显示(--show)"
grep -qF "store=$DB " "$LOG" || fail "app 未使用临时数据库"
sleep 0.6
alive

# ---- 验收 3:窗口几何 ----
read -r SW SH < <("$HELPER" screen)
WIN="$("$HELPER" windows "$APP_PID" | awk '$4 == 1064 && $5 == 454' | head -1)"
[ -n "$WIN" ] || { "$HELPER" windows "$APP_PID" >&2; fail "未找到 1064×454 窗口"; }
read -r WID WX WY WW WH <<<"$WIN"
EXPECT_X=$(( (SW - 1064) / 2 ))
echo "screen ${SW}x${SH}; panel window id=$WID at ($WX,$WY) size ${WW}x${WH}; expected x≈$EXPECT_X y=80"
[ $(( WX - EXPECT_X )) -ge -1 ] && [ $(( WX - EXPECT_X )) -le 1 ] || fail "窗口未水平居中"
[ "$WY" -eq 80 ] || fail "窗口距屏顶不是 80pt"
echo "OK geometry"

screencapture -x -o -l "$WID" "$OUT/panel-initial.png" && echo "screenshot: panel-initial.png" || echo "screencapture 不可用"

# ---- 验收 4:搜索多行终端输出中的关键词 ----
"$HELPER" type "warning"
wait_log "panel query=warning rows=[1-9]" || fail "键盘输入未送达面板(查询 warning 无日志)"
alive
echo "OK multiline query: $(grep -E 'panel query=warning ' "$LOG" | tail -1)"

"$HELPER" key esc
wait_log "panel query cleared" || fail "第一次 ESC 未清空查询"

"$HELPER" type "build"
wait_log "panel query=build rows=[1-9]" || fail "查询 build 无结果"
sleep 0.4
screencapture -x -o -l "$WID" "$OUT/panel-query-build.png" && echo "screenshot: panel-query-build.png" || true
BUILD_ROWS="$(grep -E 'panel query=build ' "$LOG" | tail -1 | sed -E 's/.*rows=([0-9]+).*/\1/')"
"$HELPER" key down $(( BUILD_ROWS + 2 ))
wait_log "panel selected=$BUILD_ROWS/$BUILD_ROWS" || fail "方向键未走到最后一项"
"$HELPER" key up $(( BUILD_ROWS + 2 ))
wait_log "panel selected=1/$BUILD_ROWS" || fail "方向键未回到第一项"
alive
echo "OK arrows over 'build' results ($BUILD_ROWS rows)"

# ---- 验收 5:空查询下方向键跨文本 / 图片 / 文件切换 ----
"$HELPER" key esc
sleep 0.3
"$HELPER" key down $(( TOTAL + 1 ))
wait_log "panel selected=$TOTAL/$TOTAL" || fail "空查询下方向键未走到最后一项"
"$HELPER" key up 3
alive
screencapture -x -o -l "$WID" "$OUT/panel-browse.png" && echo "screenshot: panel-browse.png" || true
echo "OK arrows across all $TOTAL items (text / image / file)"

# ---- ESC:查询已空,再按关闭面板 ----
"$HELPER" key esc
wait_log "panel hide" || fail "空查询时 ESC 未关闭面板"
sleep 0.5
if "$HELPER" windows "$APP_PID" | awk '$4 == 1064 && $5 == 454' | grep -q .; then
  fail "面板关闭后窗口仍在屏幕上"
fi
alive
echo "OK esc hides panel; process alive"
echo "panel smoke passed"
