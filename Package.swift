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
        // 纯逻辑(不依赖 AppKit),供单元测试使用
        .target(name: "ClipboardCore"),
        // AppKit 外壳
        .executableTarget(
            name: "ClipboardHistory",
            dependencies: ["ClipboardCore"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "ClipboardCoreTests",
            dependencies: ["ClipboardCore"]
        ),
    ]
)
