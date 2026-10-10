#!/bin/bash
# 热键 / 粘贴 / 菜单栏冒烟测试:System Events 触发 ⌘⌥C 唤出与隐藏、ESC 关闭、↩ 粘贴到 TextEdit、⌘↩ 仅复制、
# 菜单项结构、清空未固定历史(确认弹窗)、登录自启失败提示。
# 用法: scripts/ci-hotkey-smoke.sh <ClipboardHistory 可执行文件> <输出目录>
# 只在 CI 中运行:会结束正在运行的 ClipboardHistory、操作 TextEdit 并覆盖剪贴板。数据库始终是 mktemp 下的临时库。
set -euo pipefail

if [ "${CI:-}" != "true" ]; then
  echo "拒绝运行:本脚本只用于 CI(需要 CI=true)。它会退出正在运行的 ClipboardHistory、操作 TextEdit 并覆盖系统剪贴板。" >&2
  exit 2
fi

BIN="${1:?usage: $0 <ClipboardHistory binary> <output dir>}"
OUT="${2:?usage: $0 <ClipboardHistory binary> <output dir>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
DB="$WORK/history.db"
LOG="$OUT/hotkey-app.log"
HELPER="$WORK/ci-ui-helper"
APP_PID=""
mkdir -p "$OUT"

cleanup() {
  [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null || true
  osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  screencapture -x "$OUT/failure-screen.png" 2>/dev/null || true
  echo "--- app log ---" >&2
  cat "$LOG" >&2 || true
  exit 1
}

alive() { kill -0 "$APP_PID" 2>/dev/null || fail "进程已退出(崩溃?)"; }

count_log() { grep -cE "$1" "$LOG" || true; }

# 等待日志中匹配 $1 的行数达到 $2
wait_count() {
  for _ in $(seq 1 40); do
    [ "$(count_log "$1")" -ge "$2" ] && return 0
    sleep 0.2
  done
  return 1
}

# macOS 没有 timeout 命令,用 perl alarm 防止 AppleScript 卡死
with_timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }
se() { with_with_timeout 30 osascript -e "tell application \"System Events\" to $1"; }
hotkey() { se 'key code 8 using {command down, option down}'; }
panel_on_screen() { "$HELPER" windows "$APP_PID" | awk '$4 == 1064 && $5 == 454' | grep -q .; }

swiftc -O -o "$HELPER" "$SCRIPT_DIR/ci-ui-helper.swift"

# ---- 测试数据(临时库) ----
TOKEN="PASTE-TOKEN-$RANDOM$RANDOM"
NOW="$(date +%s)"
sqlite3 "$DB" <<SQL
CREATE TABLE items (
  id INTEGER PRIMARY KEY AUTOINCREMENT, kind INTEGER NOT NULL, text TEXT NOT NULL, image BLOB, thumb BLOB,
  app TEXT, created_at REAL NOT NULL, pinned INTEGER NOT NULL DEFAULT 0, content_hash TEXT NOT NULL UNIQUE);
INSERT INTO items (kind, text, app, created_at, pinned, content_hash) VALUES
 (0, 'PINNED-KEEP', 'com.apple.Terminal', $NOW - 500, 1, 'h-pinned'),
 (0, '$TOKEN', 'com.apple.Terminal', $NOW - 10, 0, 'h-token'),
 (0, 'COPY-ONLY-SECOND', 'com.apple.Safari', $NOW - 20, 0, 'h-second'),
 (0, 'older line one' || char(10) || 'older line two', 'com.apple.Terminal', $NOW - 3000, 0, 'h-old');
SQL

# ---- 启动(不带 --show) ----
pkill -x ClipboardHistory 2>/dev/null || true   # 旧实例必须先退出(坑 7)
CLIPBOARD_HISTORY_DB="$DB" "$BIN" >"$LOG" 2>&1 &
APP_PID=$!
wait_count "hotkey ⌘⌥C registered" 1 || fail "热键未注册"
grep -qF "store=$DB " "$LOG" || fail "app 未使用临时数据库"
echo "app: $(grep -E 'accessibility trusted=' "$LOG" | tail -1)"
alive

# ---- ⌘⌥C 唤出 / 隐藏 ----
hotkey
wait_count "panel show" 1 || fail "⌘⌥C 未唤出面板"
sleep 0.4
panel_on_screen || fail "唤出后面板不在屏幕上"
hotkey
wait_count "panel hide" 1 || fail "再次 ⌘⌥C 未隐藏面板"
sleep 0.3
panel_on_screen && fail "隐藏后面板仍在屏幕上"
echo "OK hotkey toggles panel"

# ---- ESC(key code 53)关闭 ----
hotkey
wait_count "panel show" 2 || fail "⌘⌥C 第二次未唤出面板"
se 'key code 53'
wait_count "panel hide" 2 || fail "ESC 未关闭面板"
alive
echo "OK esc hides panel"

# ---- ↩ 粘贴到 TextEdit ----
defaults write com.apple.TextEdit NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false
defaults write com.apple.TextEdit RichText -bool false
open -a TextEdit
sleep 2
with_timeout 30 osascript -e 'tell application "TextEdit" to make new document' -e 'tell application "TextEdit" to activate' >/dev/null
sleep 1.5
FRONT="$(se 'get name of first application process whose frontmost is true')"
echo "frontmost before hotkey: $FRONT"
[ "$FRONT" = "TextEdit" ] || fail "TextEdit 未在前台"

hotkey
wait_count "panel show" 3 || fail "TextEdit 前台时 ⌘⌥C 未唤出面板"
sleep 0.5
screencapture -x "$OUT/hotkey-panel-over-textedit.png" || true
se 'key code 36'
wait_count "choose id=[0-9]+ outcome=" 1 || fail "↩ 未选定条目"
sleep 1.5
echo "paste outcome: $(grep -E 'choose id=' "$LOG" | tail -1)"
DOC="$(with_timeout 30 osascript -e 'tell application "TextEdit" to get text of document 1')"
echo "TextEdit document: $DOC"
[ "$(pbpaste)" = "$TOKEN" ] || fail "↩ 后剪贴板不是选中条目"
case "$DOC" in
  *"$TOKEN"*) echo "OK return pastes into TextEdit" ;;
  *) fail "↩ 未把内容粘贴进 TextEdit" ;;
esac
screencapture -x "$OUT/textedit-after-paste.png" || true

# ---- ⌘↩ 仅复制 ----
hotkey
wait_count "panel show" 4 || fail "⌘⌥C 未唤出面板(第 4 次)"
se 'key code 125'
se 'key code 36 using {command down}'
wait_count "choose id=[0-9]+ outcome=copiedOnly" 1 || fail "⌘↩ 未按仅复制处理"
sleep 1
DOC2="$(with_timeout 30 osascript -e 'tell application "TextEdit" to get text of document 1')"
[ "$(pbpaste)" = "COPY-ONLY-SECOND" ] || fail "⌘↩ 后剪贴板不是第二条: $(pbpaste)"
[ "$DOC2" = "$DOC" ] || fail "⌘↩ 不应粘贴,但 TextEdit 内容变了"
echo "OK cmd-return copies only"
alive

# ---- 菜单栏 ----
MENU='menu 1 of menu bar item 1 of menu bar 2 of application process "ClipboardHistory"'
se 'click menu bar item 1 of menu bar 2 of application process "ClipboardHistory"' >/dev/null
sleep 0.5
ITEMS="$(se "get name of every menu item of $MENU")"
echo "menu items: $ITEMS"
for title in "打开面板" "登录自启" "辅助功能设置" "清空未固定历史…" "退出"; do
  case "$ITEMS" in *"$title"*) ;; *) fail "菜单缺少「$title」" ;; esac
done
se "click menu item \"打开面板\" of $MENU" >/dev/null
wait_count "panel show" 5 || fail "菜单「打开面板」未唤出面板"
sleep 0.4
screencapture -x "$OUT/menu-open-panel.png" || true
se 'key code 53'
wait_count "panel hide" 5 || fail "ESC 未关闭菜单打开的面板"
echo "OK menu items + open panel"

se 'click menu bar item 1 of menu bar 2 of application process "ClipboardHistory"' >/dev/null
sleep 0.5
se "click menu item \"清空未固定历史…\" of $MENU" >/dev/null
sleep 1
screencapture -x "$OUT/menu-clear-confirm.png" || true
se 'click button "清空" of window 1 of application process "ClipboardHistory"' >/dev/null
wait_count "cleared unpinned items" 1 || fail "确认后未清空"
REMAIN="$(sqlite3 "$DB" "SELECT group_concat(text) FROM items")"
[ "$REMAIN" = "PINNED-KEEP" ] || fail "清空后应只剩固定项,实际: $REMAIN"
echo "OK clear unpinned keeps pinned"

se 'click menu bar item 1 of menu bar 2 of application process "ClipboardHistory"' >/dev/null
sleep 0.5
se "click menu item \"登录自启\" of $MENU" >/dev/null
sleep 1
if wait_count "launch at login failed" 1; then
  ALERT="$(se 'get value of every static text of window 1 of application process "ClipboardHistory"' || true)"
  echo "login item alert: $ALERT"
  screencapture -x "$OUT/menu-login-item-alert.png" || true
  case "$ALERT" in *"/Applications"*) ;; *) fail "登录自启失败提示未提到 /Applications" ;; esac
  se 'click button "好" of window 1 of application process "ClipboardHistory"' >/dev/null
  echo "OK launch-at-login failure alert (bare binary is not an installed app)"
else
  echo "launch at login: $(grep -E 'launch at login' "$LOG" | tail -1)"
fi
alive
echo "hotkey/paste/menu smoke passed"
