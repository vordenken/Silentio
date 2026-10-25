#!/usr/bin/env swift
import CoreGraphics
import Foundation

let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let outputURL = repositoryRoot.appendingPathComponent(
    "Silentio/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.pdf"
)

var bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
guard let context = CGContext(outputURL as CFURL, mediaBox: &bounds, nil) else {
    fputs("Unable to create the menu bar icon PDF.\n", stderr)
    exit(1)
}

context.beginPDFPage(nil)
context.setFillColor(CGColor(gray: 0, alpha: 1))
context.setStrokeColor(CGColor(gray: 0, alpha: 1))
context.setLineWidth(2.1)
context.setLineCap(.round)
context.setLineJoin(.round)

// A small 3.5 mm audio plug: a specific, readable alternative to a mute glyph.
context.addPath(
    CGPath(
        roundedRect: CGRect(x: 1.5, y: 7.8, width: 5.2, height: 2.4),
        cornerWidth: 0.8,
        cornerHeight: 0.8,
        transform: nil
    ))
context.fillPath()
context.fill(CGRect(x: 6.1, y: 7.4, width: 3.0, height: 3.2))
context.addPath(
    CGPath(
        roundedRect: CGRect(x: 8.5, y: 5.7, width: 5.0, height: 6.6),
        cornerWidth: 1.4,
        cornerHeight: 1.4,
        transform: nil
    ))
context.fillPath()

// The curved cable keeps the mark legible at the actual menu bar size.
context.move(to: CGPoint(x: 12.6, y: 9))
context.addCurve(
    to: CGPoint(x: 16, y: 3.3),
    control1: CGPoint(x: 16.0, y: 9.0),
    control2: CGPoint(x: 16.0, y: 6.1)
)
context.strokePath()

// Two cut-outs suggest the insulating rings of an audio jack.
context.setBlendMode(.clear)
context.fill(CGRect(x: 3.3, y: 7.6, width: 0.65, height: 2.8))
context.fill(CGRect(x: 5.0, y: 7.6, width: 0.65, height: 2.8))
context.setBlendMode(.normal)
context.endPDFPage()
context.closePDF()

print("Generated \(outputURL.path)")
