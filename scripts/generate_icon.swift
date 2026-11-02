#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

enum AppBrand: String, CaseIterable {
    case messenger = "Messenger"
    case marketplace = "Marketplace"
    case groups = "Groups"
}

let fileManager = FileManager.default
let projectRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)

func makeContext(pixelSize: Int, colorSpace: CGColorSpace) -> CGContext? {
    guard let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    return ctx
}

func drawSquircleBackground(
    in ctx: CGContext,
    size: CGFloat,
    colorSpace: CGColorSpace,
    gradientComponents: [[CGFloat]],
    locations: [CGFloat]
) -> CGRect {
    let margin = size * 0.09765625
    let bodyRect = CGRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
    let cornerRadius = bodyRect.width * 0.225

    let squirclePath = CGPath(
        roundedRect: bodyRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.014),
        blur: size * 0.032,
        color: CGColor(gray: 0.0, alpha: 0.28)
    )
    ctx.addPath(squirclePath)
    ctx.setFillColor(CGColor(red: 0.05, green: 0.45, blue: 0.95, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    let colors = gradientComponents.compactMap { CGColor(colorSpace: colorSpace, components: $0) }
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: bodyRect.minX, y: bodyRect.minY),
            end: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    ctx.addPath(squirclePath)
    ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.22))
    ctx.setLineWidth(max(1.0, size * 0.006))
    ctx.strokePath()
    ctx.restoreGState()

    return bodyRect
}

func drawMessengerSymbol(in ctx: CGContext, size: CGFloat, bodyRect: CGRect) {
    let cx = size * 0.5
    let cy = size * 0.525
    let rx = bodyRect.width * 0.305
    let ry = bodyRect.height * 0.278

    let bubblePath = CGMutablePath()
    let tailBaseLeftAngle: CGFloat = -.pi * 0.72
    let tailBaseRightAngle: CGFloat = -.pi * 0.55

    let steps = 120
    let startAngle = tailBaseRightAngle
    let endAngle = tailBaseLeftAngle + .pi * 2.0
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let angle = startAngle + (endAngle - startAngle) * t
        let px = cx + rx * cos(angle)
        let py = cy + ry * sin(angle)
        if i == 0 {
            bubblePath.move(to: CGPoint(x: px, y: py))
        } else {
            bubblePath.addLine(to: CGPoint(x: px, y: py))
        }
    }

    let tailTip = CGPoint(x: cx - rx * 0.62, y: cy - ry * 1.24)
    bubblePath.addQuadCurve(
        to: tailTip,
        control: CGPoint(x: cx - rx * 0.66, y: cy - ry * 0.95)
    )
    let rightJoin = CGPoint(
        x: cx + rx * cos(tailBaseRightAngle),
        y: cy + ry * sin(tailBaseRightAngle)
    )
    bubblePath.addQuadCurve(
        to: rightJoin,
        control: CGPoint(x: cx - rx * 0.34, y: cy - ry * 1.12)
    )
    bubblePath.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.008),
        blur: size * 0.02,
        color: CGColor(gray: 0.0, alpha: 0.16)
    )

    let combinedPath = CGMutablePath()
    combinedPath.addPath(bubblePath)

    let bolt = CGMutablePath()
    let bw = rx * 1.08
    let bh = ry * 0.56
    bolt.move(to: CGPoint(x: cx - bw * 0.52, y: cy - bh * 0.36))
    bolt.addLine(to: CGPoint(x: cx - bw * 0.05, y: cy + bh * 0.44))
    bolt.addLine(to: CGPoint(x: cx + bw * 0.13, y: cy + bh * 0.02))
    bolt.addLine(to: CGPoint(x: cx + bw * 0.52, y: cy + bh * 0.36))
    bolt.addLine(to: CGPoint(x: cx + bw * 0.05, y: cy - bh * 0.44))
    bolt.addLine(to: CGPoint(x: cx - bw * 0.13, y: cy - bh * 0.02))
    bolt.closeSubpath()

    combinedPath.addPath(bolt)
    ctx.addPath(combinedPath)
    ctx.setFillColor(CGColor(gray: 1.0, alpha: 0.98))
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
}

func drawMarketplaceSymbol(in ctx: CGContext, size: CGFloat, bodyRect: CGRect) {
    let cx = size * 0.5
    let cy = size * 0.495
    let w = bodyRect.width * 0.56
    let h = bodyRect.height * 0.52

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.009),
        blur: size * 0.022,
        color: CGColor(gray: 0.0, alpha: 0.18)
    )
    ctx.setFillColor(CGColor(gray: 1.0, alpha: 0.98))

    // 1. Storefront base walls + open doorway cutout (even-odd)
    let baseWidth = w * 0.84
    let baseHeight = h * 0.52
    let baseMinX = cx - baseWidth * 0.5
    let baseMinY = cy - h * 0.47
    let baseRect = CGRect(x: baseMinX, y: baseMinY, width: baseWidth, height: baseHeight)
    let wallCorner = w * 0.06

    let basePath = CGMutablePath()
    basePath.addPath(
        CGPath(roundedRect: baseRect, cornerWidth: wallCorner, cornerHeight: wallCorner, transform: nil)
    )

    // Doorway cutout on the left-center (flat bottom flush with storefront floor, arched top)
    let doorWidth = baseWidth * 0.30
    let doorHeight = baseHeight * 0.68
    let doorX = baseMinX + baseWidth * 0.14
    let doorArchR = doorWidth * 0.5
    let doorCutout = CGMutablePath()
    doorCutout.move(to: CGPoint(x: doorX, y: baseMinY))
    doorCutout.addLine(to: CGPoint(x: doorX, y: baseMinY + doorHeight - doorArchR))
    doorCutout.addArc(
        center: CGPoint(x: doorX + doorArchR, y: baseMinY + doorHeight - doorArchR),
        radius: doorArchR,
        startAngle: .pi,
        endAngle: 0,
        clockwise: true
    )
    doorCutout.addLine(to: CGPoint(x: doorX + doorWidth, y: baseMinY))
    doorCutout.closeSubpath()
    basePath.addPath(doorCutout)

    let winWidth = baseWidth * 0.32
    let winHeight = baseHeight * 0.42
    let winRect = CGRect(
        x: baseMinX + baseWidth * 0.54,
        y: baseMinY + baseHeight * 0.30,
        width: winWidth,
        height: winHeight
    )
    basePath.addPath(
        CGPath(roundedRect: winRect, cornerWidth: winWidth * 0.22, cornerHeight: winWidth * 0.22, transform: nil)
    )

    ctx.addPath(basePath)
    ctx.fillPath(using: .evenOdd)

    // 2. Classic 4-scallop Marketplace awning roof above the storefront
    let awningTopY = cy + h * 0.48
    let awningScallopCenterY = cy + h * 0.17
    let awningTopWidth = w * 0.78
    let awningBottomWidth = w * 1.02
    let scallopCount = 4
    let scallopRadius = awningBottomWidth / CGFloat(scallopCount * 2)

    let awningPath = CGMutablePath()
    let topLeft = CGPoint(x: cx - awningTopWidth * 0.5, y: awningTopY)
    let topRight = CGPoint(x: cx + awningTopWidth * 0.5, y: awningTopY)
    let bottomLeftX = cx - awningBottomWidth * 0.5
    let bottomRightX = cx + awningBottomWidth * 0.5
    let topCornerR = w * 0.055

    awningPath.move(to: CGPoint(x: bottomLeftX, y: awningScallopCenterY))
    awningPath.addLine(to: CGPoint(x: topLeft.x - topCornerR * 0.3, y: awningTopY - topCornerR))
    awningPath.addQuadCurve(
        to: CGPoint(x: topLeft.x + topCornerR, y: awningTopY),
        control: topLeft
    )
    awningPath.addLine(to: CGPoint(x: topRight.x - topCornerR, y: awningTopY))
    awningPath.addQuadCurve(
        to: CGPoint(x: topRight.x + topCornerR * 0.3, y: awningTopY - topCornerR),
        control: topRight
    )
    awningPath.addLine(to: CGPoint(x: bottomRightX, y: awningScallopCenterY))

    // Scalloped bottom edge from right to left (4 semicircular scallops hanging downward)
    for i in stride(from: scallopCount - 1, through: 0, by: -1) {
        let scx = bottomLeftX + scallopRadius * (CGFloat(i) * 2.0 + 1.0)
        awningPath.addArc(
            center: CGPoint(x: scx, y: awningScallopCenterY),
            radius: scallopRadius,
            startAngle: 0,
            endAngle: .pi,
            clockwise: true
        )
    }
    awningPath.closeSubpath()

    ctx.addPath(awningPath)
    ctx.fillPath()
    ctx.restoreGState()
}

func drawGroupsSymbol(in ctx: CGContext, size: CGFloat, bodyRect: CGRect) {
    let cx = size * 0.5
    let cy = size * 0.49
    let unit = bodyRect.width

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.009),
        blur: size * 0.022,
        color: CGColor(gray: 0.0, alpha: 0.18)
    )

    // Helper for a smooth person silhouette (circle head + rounded shoulder dome)
    func personPath(centerX: CGFloat, baseY: CGFloat, scale: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let headR = unit * 0.095 * scale
        let headCY = baseY + unit * 0.255 * scale
        p.addEllipse(in: CGRect(x: centerX - headR, y: headCY - headR, width: headR * 2, height: headR * 2))

        let shW = unit * 0.31 * scale
        let shH = unit * 0.165 * scale
        let shMinX = centerX - shW * 0.5
        let bottomCorner = shW * 0.16

        p.move(to: CGPoint(x: shMinX + bottomCorner, y: baseY))
        p.addLine(to: CGPoint(x: shMinX + shW - bottomCorner, y: baseY))
        p.addQuadCurve(
            to: CGPoint(x: shMinX + shW, y: baseY + bottomCorner),
            control: CGPoint(x: shMinX + shW, y: baseY)
        )
        p.addCurve(
            to: CGPoint(x: centerX, y: baseY + shH),
            control1: CGPoint(x: shMinX + shW, y: baseY + shH * 0.78),
            control2: CGPoint(x: centerX + shW * 0.34, y: baseY + shH)
        )
        p.addCurve(
            to: CGPoint(x: shMinX, y: baseY + bottomCorner),
            control1: CGPoint(x: centerX - shW * 0.34, y: baseY + shH),
            control2: CGPoint(x: shMinX, y: baseY + shH * 0.78)
        )
        p.addQuadCurve(
            to: CGPoint(x: shMinX + bottomCorner, y: baseY),
            control: CGPoint(x: shMinX, y: baseY)
        )
        p.closeSubpath()
        return p
    }

    // Subtle outer community ring
    let ringR = unit * 0.355
    ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.26))
    ctx.setLineWidth(max(1.5, unit * 0.028))
    ctx.strokeEllipse(in: CGRect(x: cx - ringR, y: cy - ringR, width: ringR * 2, height: ringR * 2))

    // Left & right background members (slightly translucent white for clean depth)
    let sideOffset = unit * 0.195
    let sideBaseY = cy - unit * 0.135
    ctx.setFillColor(CGColor(gray: 1.0, alpha: 0.78))
    ctx.addPath(personPath(centerX: cx - sideOffset, baseY: sideBaseY, scale: 0.80))
    ctx.fillPath()
    ctx.addPath(personPath(centerX: cx + sideOffset, baseY: sideBaseY, scale: 0.80))
    ctx.fillPath()

    // Prominent foreground center member
    let centerBaseY = cy - unit * 0.175
    ctx.setFillColor(CGColor(gray: 1.0, alpha: 0.99))
    ctx.addPath(personPath(centerX: cx, baseY: centerBaseY, scale: 1.04))
    ctx.fillPath()

    ctx.restoreGState()
}

func renderIcon(brand: AppBrand, pixelSize: Int) -> Data? {
    let size = CGFloat(pixelSize)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = makeContext(pixelSize: pixelSize, colorSpace: colorSpace)
    else {
        return nil
    }

    switch brand {
    case .messenger:
        let bodyRect = drawSquircleBackground(
            in: ctx,
            size: size,
            colorSpace: colorSpace,
            gradientComponents: [
                [0.00, 0.56, 1.00, 1.0],
                [0.58, 0.22, 1.00, 1.0],
                [1.00, 0.33, 0.52, 1.0]
            ],
            locations: [0.0, 0.55, 1.0]
        )
        drawMessengerSymbol(in: ctx, size: size, bodyRect: bodyRect)

    case .marketplace:
        // Distinct Marketplace Ocean-Teal -> Emerald-Aqua palette (instantly distinguishable from Groups blue & Messenger violet)
        let bodyRect = drawSquircleBackground(
            in: ctx,
            size: size,
            colorSpace: colorSpace,
            gradientComponents: [
                [0.00, 0.46, 0.76, 1.0],
                [0.00, 0.68, 0.78, 1.0],
                [0.08, 0.85, 0.64, 1.0]
            ],
            locations: [0.0, 0.52, 1.0]
        )
        drawMarketplaceSymbol(in: ctx, size: size, bodyRect: bodyRect)

    case .groups:
        // Vibrant Groups Deep Indigo -> Royal Blue -> Sky Cyan palette
        let bodyRect = drawSquircleBackground(
            in: ctx,
            size: size,
            colorSpace: colorSpace,
            gradientComponents: [
                [0.06, 0.24, 0.78, 1.0],
                [0.09, 0.47, 0.95, 1.0],
                [0.20, 0.78, 1.00, 1.0]
            ],
            locations: [0.0, 0.52, 1.0]
        )
        drawGroupsSymbol(in: ctx, size: size, bodyRect: bodyRect)
    }

    guard let cgImage = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])
}

struct IconSpec {
    let pointSize: Int
    let scale: Int
    var pixelSize: Int { pointSize * scale }
    var filename: String {
        scale == 1 ? "icon_\(pointSize)x\(pointSize).png" : "icon_\(pointSize)x\(pointSize)@2x.png"
    }
}

let specs: [IconSpec] = [
    IconSpec(pointSize: 16, scale: 1),
    IconSpec(pointSize: 16, scale: 2),
    IconSpec(pointSize: 32, scale: 1),
    IconSpec(pointSize: 32, scale: 2),
    IconSpec(pointSize: 128, scale: 1),
    IconSpec(pointSize: 128, scale: 2),
    IconSpec(pointSize: 256, scale: 1),
    IconSpec(pointSize: 256, scale: 2),
    IconSpec(pointSize: 512, scale: 1),
    IconSpec(pointSize: 512, scale: 2)
]

let imagesJSON = specs.map { spec in
    """
        {
          "filename" : "\(spec.filename)",
          "idiom" : "mac",
          "scale" : "\(spec.scale)x",
          "size" : "\(spec.pointSize)x\(spec.pointSize)"
        }
    """
}.joined(separator: ",\n")

let appIconContentsJSON = """
{
  "images" : [
\(imagesJSON)
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

let rootAssetsJSON = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

func accentColorJSON(r: String, g: String, b: String) -> String {
    """
    {
      "colors" : [
        {
          "color" : {
            "color-space" : "display-p3",
            "components" : {
              "alpha" : "1.000",
              "blue" : "\(b)",
              "green" : "\(g)",
              "red" : "\(r)"
            }
          },
          "idiom" : "universal"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
}

for brand in AppBrand.allCases {
    let assetsDir = projectRoot.appendingPathComponent("\(brand.rawValue)/Resources/Assets.xcassets")
    let appIconDir = assetsDir.appendingPathComponent("AppIcon.appiconset")
    let accentDir = assetsDir.appendingPathComponent("AccentColor.colorset")

    try fileManager.createDirectory(at: appIconDir, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: accentDir, withIntermediateDirectories: true)

    try rootAssetsJSON.write(to: assetsDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

    let accent: String
    switch brand {
    case .messenger:
        accent = accentColorJSON(r: "0.040", g: "0.520", b: "1.000")
    case .marketplace:
        accent = accentColorJSON(r: "0.000", g: "0.620", b: "0.880")
    case .groups:
        accent = accentColorJSON(r: "0.090", g: "0.470", b: "0.950")
    }
    try accent.write(to: accentDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

    for spec in specs {
        guard let png = renderIcon(brand: brand, pixelSize: spec.pixelSize) else {
            fputs("Failed to generate \(brand.rawValue) \(spec.filename)\n", stderr)
            exit(1)
        }
        try png.write(to: appIconDir.appendingPathComponent(spec.filename))
    }

    try appIconContentsJSON.write(
        to: appIconDir.appendingPathComponent("Contents.json"),
        atomically: true,
        encoding: .utf8
    )
    print("Generated \(brand.rawValue) AppIcon.appiconset (\(specs.count) PNGs)")
}
