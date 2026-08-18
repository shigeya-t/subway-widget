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
        URL(fileURLWithPath: "WidgetExtension/Assets.xcassets/AppIcon.appiconset"),
    ]
}()

let macSizes: [(name: String, pixels: Int)] = [
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

/// ウィジェット編集・設定は iOS 由来で、60pt / 76pt を Assets.car からも探す。
let catalogIOSSizes: [(name: String, pixels: Int)] = [
    ("AppIcon60x60@2x.png", 120),
    ("AppIcon60x60@3x.png", 180),
    ("AppIcon76x76@2x.png", 152),
]

/// ファイル名参照 (CFBundleIconFiles) 用。`~ipad` はカタログには載せない（unassigned child になる）。
let resourceIOSSizes: [(name: String, pixels: Int)] = catalogIOSSizes + [
    ("AppIcon76x76@2x~ipad.png", 152),
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

let contentsJSON = """
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" },
    { "filename" : "AppIcon60x60@2x.png", "idiom" : "iphone", "scale" : "2x", "size" : "60x60" },
    { "filename" : "AppIcon60x60@3x.png", "idiom" : "iphone", "scale" : "3x", "size" : "60x60" },
    { "filename" : "AppIcon76x76@2x.png", "idiom" : "ipad", "scale" : "2x", "size" : "76x76" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""

for dest in destinations {
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    for item in macSizes + catalogIOSSizes {
        let url = dest.appendingPathComponent(item.name)
        try render(pixels: item.pixels).write(to: url)
        print("wrote \(url.path) (\(item.pixels)px)")
    }
    try contentsJSON.write(
        to: dest.appendingPathComponent("Contents.json"),
        atomically: true,
        encoding: .utf8
    )
}

// ファイル名参照 (CFBundleIconFiles) 用。Assets.car に無いときウィジェット一覧がこれを探す。
let iosIconDirs = [
    URL(fileURLWithPath: "App/Resources"),
    URL(fileURLWithPath: "WidgetExtension/Resources"),
]
for dir in iosIconDirs {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for item in resourceIOSSizes {
        let url = dir.appendingPathComponent(item.name)
        try render(pixels: item.pixels).write(to: url)
        print("wrote \(url.path) (\(item.pixels)px)")
    }
}
