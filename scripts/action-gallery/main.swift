import AppKit
import CoreGraphics
import QuartzCore
import ImageIO
import UniformTypeIdentifiers

// Render the application's actual scene rig; no global input capture or UI windows.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let settings = CatSettings.shared
settings.coatTheme = .customTuxedo
settings.eyeTheme = .photoOlive
settings.showKeyBadges = true
settings.customAutoActions = false

let frame = CGRect(x: 0, y: 0, width: 360, height: 320)
let epoch = CACurrentMediaTime()
let previews: [(CustomCatAction, String, String)] = [
    (.wave, "wave", "wave"),
    (.nap, "nap", "rest_side"),
    (.observe, "observe", "observe"),
    (.belly, "belly", "belly_hug"),
    (.groom, "groom", "groom_leg")
]

func advance(_ cat: CatPhysics, at t: Double, dt: Double = 1.0 / 60) {
    cat.step(dt: CGFloat(dt), windowFrameInScreen: frame, scripted: ScriptedFrameInput(
        now: epoch + t, activeKeys: [], orderedKeys: [],
        mouseScreenPos: CGPoint(x: 180 + 280 * sin(t * 1.4), y: 220 + 140 * cos(t * 1.4)),
        mouseVelocity: .zero, leftMouseDown: false, rightMouseDown: false,
        lastMouseMoveTime: epoch + t, lastMouseClickTime: 0, lastKeyActivityTime: 0,
        trackingScreen: CGRect(x: -360, y: -320, width: 1080, height: 960)))
}

func render(_ cat: CatPhysics) -> CGImage {
    let context = CGContext(data: nil, width: 720, height: 640, bitsPerComponent: 8,
        bytesPerRow: 720 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: 640)
    context.scaleBy(x: 2, y: -2)
    CatRenderer.draw(in: context, physics: cat, showPermissionPill: false)
    return context.makeImage()!
}

for (action, filename, expectedPose) in previews {
    let cat = CatPhysics()
    cat.playCustomAction(action, duration: 60, manual: true)
    for n in 0..<60 { advance(cat, at: Double(n) / 60) }
    precondition(cat.customDisplayedPose == expectedPose && cat.customPoseOpacity > 0.99)
    let destination = CGImageDestinationCreateWithURL(
        output.appendingPathComponent(filename + ".gif") as CFURL,
        UTType.gif.identifier as CFString, 150, nil)!
    CGImageDestinationSetProperties(destination, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
    ] as CFDictionary)
    for n in 0..<150 {
        for step in 0..<3 { advance(cat, at: 1 + Double(n * 3 + step) / 75, dt: 1.0 / 75) }
        precondition(cat.customDisplayedPose == expectedPose)
        let image = render(cat)
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.04]
        ] as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(destination))
    print("Rendered \(filename): \(expectedPose), 150 frames, 6 seconds")
}
