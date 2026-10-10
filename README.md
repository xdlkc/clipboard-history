# ClipboardHistory

原生 macOS 菜单栏剪贴板历史工具(Swift + AppKit,纯 Swift Package Manager,最低 macOS 13)。

> 当前进度:菜单栏常驻,后台捕获剪贴板并写入 SQLite 历史(`~/Library/Application Support/ClipboardHistory/history.db`);主面板可用 `--show` 启动参数打开。模拟粘贴、全局热键与菜单项、打包会在后续 PR 中加入。

## 结构

- `Sources/ClipboardCore`:纯逻辑库(不依赖 AppKit):`Fuzzy`、`rowText`、`Store`(SQLite)、内容 SHA256
- `Sources/ClipboardCapture`:剪贴板读取 / 写回与缩略图(依赖 AppKit,不含 UI)
- `Sources/ClipboardHistory`:AppKit 外壳(菜单栏常驻,无 Dock 图标;`ClipboardMonitor` 0.35s 轮询)
- `Tests/`:XCTest 单元测试;`scripts/ci-capture-smoke.sh`:CI 中的真实剪贴板捕获冒烟测试(仅在 `CI=true` 时运行,使用临时数据库)
- `design/panel.html`:主面板高保真稿源码(颜色、间距以此为准)
- `Info.plist`:组装 .app 时使用(`LSUIElement`、`CFBundleIconFile=AppIcon`、版本号)

设置环境变量 `CLIPBOARD_HISTORY_DB=<路径>` 可让应用改用指定的数据库文件,测试时不会碰到真实历史。

## 构建与测试

只需 Xcode Command Line Tools:

```sh
swift build -c release --arch arm64
swift build -c release --arch x86_64
lipo -create \
  "$(swift build -c release --arch arm64 --show-bin-path)/ClipboardHistory" \
  "$(swift build -c release --arch x86_64 --show-bin-path)/ClipboardHistory" \
  -output ClipboardHistory
lipo -info ClipboardHistory
swift test
```

两种架构的产物分别位于 `.build/<triple>/release/`,不要依赖 `.build/release` 软链。

CI(GitHub Actions,macOS 运行器)在每次 push 与 PR 上执行以上步骤,并上传通用二进制。
