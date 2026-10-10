# ClipboardHistory

原生 macOS 菜单栏剪贴板历史工具(Swift + AppKit,纯 Swift Package Manager,最低 macOS 13)。

> 当前为骨架阶段:菜单栏图标 + 退出菜单,以及可单元测试的模糊匹配 / 列表行文本逻辑。存储、捕获、主面板、粘贴与热键、打包会在后续 PR 中加入。

## 结构

- `Sources/ClipboardCore`:纯逻辑库(不依赖 AppKit),包含 `Fuzzy` 子序列模糊匹配与 `rowText` 列表行文本
- `Sources/ClipboardHistory`:AppKit 外壳(菜单栏常驻,无 Dock 图标)
- `Tests/ClipboardCoreTests`:XCTest 单元测试
- `Info.plist`:组装 .app 时使用(`LSUIElement`、`CFBundleIconFile=AppIcon`、版本号)

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
