#!/usr/bin/env swift
import AppKit

/// 単色背景に大きな車両正面を載せた macOS 用 AppIcon 一式を書き出す。
/// 実行: swift scripts/generate-app-icon.swift

let destinations: [URL] = {
    if CommandLine.arguments.count > 1 {
        return CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
    }
    return [
        URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset"),
    ]
}()

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let background = NSColor(srgbRed: 0xB6 / 255, green: 0x00 / 255, blue: 0x7A / 255, alpha: 1) // 大江戸

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("CGContext")
    }

    ctx.setFillColor(background.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    drawTram(in: ctx, size: size)

    guard let cgImage = ctx.makeImage() else { fatalError("makeImage") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    return data
}

func drawTram(in ctx: CGContext, size: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: size / 2, y: size / 2)
    let scale = size * 0.86 / 84
    ctx.scaleBy(x: scale, y: scale)

    ctx.setFillColor(NSColor.white.cgColor)

    let body = CGRect(x: -42, y: -40, width: 84, height: 80)
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: 16, cornerHeight: 16, transform: nil))
    ctx.fillPath()

    ctx.setFillColor(background.cgColor)
    ctx.fill(CGRect(x: -30, y: 0, width: 26, height: 26))
    ctx.fill(CGRect(x: 4, y: 0, width: 26, height: 26))
    ctx.fillEllipse(in: CGRect(x: -28, y: -28, width: 16, height: 16))
    ctx.fillEllipse(in: CGRect(x: 12, y: -28, width: 16, height: 16))
    ctx.restoreGState()
}

for dest in destinations {
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    for item in sizes {
        let url = dest.appendingPathComponent(item.name)
        try render(pixels: item.pixels).write(to: url)
        print("wrote \(url.path) (\(item.pixels)px)")
    }
    let contents = dest.appendingPathComponent("Contents.json")
    if !FileManager.default.fileExists(atPath: contents.path) {
        try? FileManager.default.copyItem(
            at: URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset/Contents.json"),
            to: contents
        )
    }
}

let imageSets = [
    "App/Assets.xcassets/ToeiIcon.imageset",
    "WidgetExtension/Assets.xcassets/ToeiIcon.imageset",
]
let master = destinations[0]
for path in imageSets {
    let dir = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for name in ["ToeiIcon.png", "ToeiIcon@2x.png"] {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
    }
    try FileManager.default.copyItem(
        at: master.appendingPathComponent("icon_128x128.png"),
        to: dir.appendingPathComponent("ToeiIcon.png")
    )
    try FileManager.default.copyItem(
        at: master.appendingPathComponent("icon_256x256.png"),
        to: dir.appendingPathComponent("ToeiIcon@2x.png")
    )
    let json = """
    {
      "images" : [
        { "filename" : "ToeiIcon.png", "idiom" : "universal", "scale" : "1x" },
        { "filename" : "ToeiIcon@2x.png", "idiom" : "universal", "scale" : "2x" }
      ],
      "info" : { "author" : "xcode", "version" : 1 },
      "properties" : { "template-rendering-intent" : "original" }
    }
    """
    try json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("wrote \(path)")
}

// macOS 26 のウィジェットギャラリーは iOS 由来で、CFBundleIcons / AppIcon60x60 を探す。
// 無いと Xcode の格子プレースホルダになる（ThreadMaster 等の iOS アプリと同じ経路）。
let iosIconDirs = [
    URL(fileURLWithPath: "App/Resources"),
    URL(fileURLWithPath: "WidgetExtension/Resources"),
]
let iosIcons: [(name: String, pixels: Int)] = [
    ("AppIcon60x60@2x.png", 120),
    ("AppIcon60x60@3x.png", 180),
    ("AppIcon76x76@2x.png", 152),
    ("AppIcon76x76@2x~ipad.png", 152),
]
for dir in iosIconDirs {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for item in iosIcons {
        let url = dir.appendingPathComponent(item.name)
        try render(pixels: item.pixels).write(to: url)
        print("wrote \(url.path) (\(item.pixels)px)")
    }
}



