// 1024 设计图 → 全尺寸 iconset → AppIcon.icns
// 用法: swiftc -O make-icon.swift -o build/make-icon && build/make-icon assets/icon-1024.png build/AppIcon.icns [iconset 目录]
// 不给 iconset 目录时用临时目录并在结束后删除。
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 3 || args.count == 4 else {
    die("usage: make-icon <icon-1024.png> <AppIcon.icns> [iconset-dir]")
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let keepIconset = args.count == 4
let iconset = keepIconset
    ? URL(fileURLWithPath: args[3])
    : FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")

guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    die("cannot read \(input.path)")
}
guard image.width == 1024, image.height == 1024 else {
    die("expected 1024×1024, got \(image.width)×\(image.height)")
}

/// iconutil 要求的 10 个文件:16/32/128/256/512 各 @1x 与 @2x。
let variants: [(points: Int, scale: Int)] = [16, 32, 128, 256, 512].flatMap { [($0, 1), ($0, 2)] }

func render(pixels: Int) -> CGImage {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        die("cannot create \(pixels)px context")
    }
    let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    let radius = 0.225 * CGFloat(pixels)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(image, in: rect)
    guard let result = ctx.makeImage() else { die("cannot render \(pixels)px") }
    return result
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        die("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { die("cannot finalize \(url.path)") }
}

let fm = FileManager.default
try? fm.removeItem(at: iconset)
do {
    try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
    try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
} catch {
    die("\(error)")
}

for v in variants {
    let name = v.scale == 1 ? "icon_\(v.points)x\(v.points).png" : "icon_\(v.points)x\(v.points)@2x.png"
    writePNG(render(pixels: v.points * v.scale), to: iconset.appendingPathComponent(name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
do {
    try iconutil.run()
} catch {
    die("iconutil: \(error)")
}
iconutil.waitUntilExit()
if !keepIconset { try? fm.removeItem(at: iconset) }
guard iconutil.terminationStatus == 0 else { die("iconutil exited with \(iconutil.terminationStatus)") }
print("make-icon: \(variants.count) sizes → \(output.path)")
