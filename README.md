# ClipboardHistory

原生 macOS 菜单栏剪贴板历史工具(Swift + AppKit,纯 Swift Package Manager,最低 macOS 13)。常驻菜单栏、没有 Dock 图标,按 ⌘⌥C 唤出面板,可以模糊搜索,按 ↩ 粘贴到当前应用。

## 结构

- `Sources/ClipboardCore`:纯逻辑库(不依赖 AppKit):`Fuzzy`、`rowText`、`Store`(SQLite)、内容 SHA256、面板 / 粘贴 / 菜单逻辑
- `Sources/ClipboardCapture`:剪贴板读取 / 写回与缩略图(依赖 AppKit,不含 UI)
- `Sources/ClipboardHistory`:AppKit 外壳(菜单栏、面板、Carbon 热键、模拟 ⌘V)
- `Tests/`:XCTest 单元测试;`scripts/ci-*.sh`:CI 中的冒烟测试(仅在 `CI=true` 时运行,使用临时数据库)
- `design/panel.html`:主面板高保真稿源码;`assets/icon-1024.png`:图标源图(1024 满版方图,圆角由 `make-icon.swift` 加)
- `Info.plist`:组装 .app 时使用(`LSUIElement`、`CFBundleIconFile=AppIcon`、版本号;发版时递增第三位)
- `build.sh` / `package.sh` / `make-icon.swift`:构建、分发打包、生成图标;`packaging/安装说明.txt`:随包附带的说明

设置环境变量 `CLIPBOARD_HISTORY_DB=<路径>` 可让应用改用指定的数据库文件,测试时不会碰到真实历史。

## 开机自启动

将应用安装到 `/Applications` 并运行,在菜单栏点击「登录自启」即可开启/关闭。
这里的自启指当前用户登录 macOS 后启动应用;首次使用默认关闭(已有系统登录项会沿用)。
勾选表示已启用,横线表示已注册但仍需系统批准;开启后需要批准时可直接打开系统设置。
等待批准时再次点击菜单项可取消注册。

`ClipboardCore.LaunchAtLoginController` 提供 `setEnabled(_:)`、`status`、`refresh()` 和
`savedEnabled`,通过 `LaunchAtLoginService` 注入系统服务或测试替身。
应用层使用 [SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)
管理登录项,系统保存实际注册关系;`UserDefaults` 的 `launchAtLoginEnabled` 保存最近同步的注册配置
(包含待批准请求,不等同于实际已启用)。启动和打开菜单时同步系统状态,不会按旧配置自动重新注册,
因此用户在系统设置中的修改会被尊重。注册/注销失败会提示错误,不会将失败请求保存为成功。
单元测试使用独立偏好设置域和系统服务替身,不会修改真实登录项。

手动验收:从 `/Applications` 打开应用 → 开启「登录自启」(若需要则批准) → 退出并重新登录,
确认菜单栏应用启动;关闭后再次登录,确认不再启动。也可从系统设置撤销批准,重新打开菜单确认横线状态。

## 开发与测试

只需 Xcode Command Line Tools:

```sh
swift build -c release --arch arm64
swift build -c release --arch x86_64
swift test
```

两种架构的产物分别位于 `.build/<triple>/release/`,不要依赖 `.build/release` 软链。

## 本机构建:`build.sh`

```sh
./build.sh                 # 有自签名证书用证书签名,否则退回 ad-hoc
SIGN=adhoc ./build.sh      # 强制 ad-hoc
```

两架构分别构建 → `lipo` 合成通用二进制 → 由 `assets/icon-1024.png` 生成 `AppIcon.icns`(不入库,每次构建重新生成)→ 组装 `build/ClipboardHistory.app` → `codesign`。

装到本机:先退出正在运行的 ClipboardHistory,再把 `build/ClipboardHistory.app` 拷到 `/Applications`(替换旧版本)。

### 自签名证书(让替换后的新版本保留辅助功能授权)

辅助功能授权跟着代码签名走。ad-hoc 签名每次重编都会变,替换 /Applications 里的副本后就要重新授权。用固定的自签名证书签名后,替换不需要重新授权。证书只需建一次;不要在 CI 里建证书。

```sh
cd "$(mktemp -d)"
cat > cert.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = ClipboardHistory Self-Signed
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config cert.cnf -keyout key.pem -out cert.pem
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -name "ClipboardHistory Self-Signed" -out cert.p12 -passout pass:tmp
security import cert.p12 -k ~/Library/Keychains/login.keychain-db -P tmp -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem
security find-identity -v -p codesigning     # 应列出 "ClipboardHistory Self-Signed"
rm -f key.pem cert.p12
```

- 用的是系统自带的 `/usr/bin/openssl`(LibreSSL)。如果换成 Homebrew 的 OpenSSL 3,`pkcs12 -export` 要加 `-legacy`,否则钥匙串导入不了。
- `add-trusted-cert` 会弹出系统密码框;第一次用证书签名时,钥匙串可能会询问是否允许 codesign 使用私钥,选「始终允许」。
- 证书名称可以不一样,构建时用 `SIGN_IDENTITY="你的证书名" ./build.sh` 指定。
- 换成证书签名后的第一次,需要在「系统设置 › 隐私与安全性 › 辅助功能」里删掉旧条目、重新添加一次;之后再替换就不用了。

## 分发打包:`package.sh`

```sh
./package.sh
```

强制 ad-hoc 签名构建,生成 `dist/ClipboardHistory-<版本>.zip` 和 `.dmg`。两者都包含 app 和《安装说明.txt》,dmg 里另有指向 /Applications 的链接。打包后会解压 zip、挂载 dmg 各校验一次签名,最后删除全部中间 .app 与目录,只留下 zip 和 dmg。版本号取自 `Info.plist` 的 `CFBundleShortVersionString`。

## CI

GitHub Actions(macOS 运行器)只在 PR(pull_request)和推送到 main 时运行;只改了 `*.md`、`docs/`、`design/`、`packaging/*.txt` 时跳过。同一分支有新提交时,会取消还在跑的旧运行。

- macOS 15 任务(完整):两架构分别构建并 `lipo` 合成通用二进制、单元测试(全部开启 `-warnings-as-errors`)、剪贴板捕获 / 面板 / 热键 / 粘贴 / 菜单冒烟测试、`SIGN=adhoc ./package.sh` 并校验签名、zip、dmg 与 `lipo -info`。
- macOS 26 SDK 任务(精简):`swift build -c release --arch arm64` 与 `swift test`。
- 构建包:zip + dmg、图标预览、冒烟截图、通用二进制。

## GitHub Release 包

最低 macOS 13，Universal ZIP / DMG 均包含 arm64 与 x86_64。
`Release packages` 在 PR、main、release/** 分支和手动运行时生成经过校验的 Actions 产物；
两种原生运行器下载同一份包，校验 SHA256、架构、部署目标、签名与原生启动。
推送与应用版本完全相同的 `v<major>.<minor>.<patch>` tag 后，所有检查通过才创建 **draft Release**。
在 GitHub 审阅后手动发布；工作流不会自动对外发布正式版本，也不会合并 PR。
下载 ZIP、DMG 和 SHA256SUMS 后，在同一目录运行 `shasum -a 256 -c SHA256SUMS`。
当前分发包仅 ad-hoc 签名，没有 Developer ID 签名或 Apple 公证，可能出现 Gatekeeper 提示。
CI 使用 macOS 15；最低系统由 plist 与每个 Mach-O 切片的部署目标检查，未替代 macOS 13 真机测试。
