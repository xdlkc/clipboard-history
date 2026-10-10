// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClipboardHistory",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClipboardHistory", targets: ["ClipboardHistory"]),
        .library(name: "ClipboardCore", targets: ["ClipboardCore"]),
    ],
    targets: [
        // 纯逻辑(不依赖 AppKit):Fuzzy、rowText、Store、hash
        .target(
            name: "ClipboardCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // 剪贴板读写(依赖 AppKit,但不含 UI),可在测试中针对命名剪贴板运行
        .target(
            name: "ClipboardCapture",
            dependencies: ["ClipboardCore"]
        ),
        // AppKit 外壳
        .executableTarget(
            name: "ClipboardHistory",
            dependencies: ["ClipboardCore", "ClipboardCapture"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "ClipboardCoreTests",
            dependencies: ["ClipboardCore"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "ClipboardCaptureTests",
            dependencies: ["ClipboardCapture", "ClipboardCore"]
        ),
    ]
)
