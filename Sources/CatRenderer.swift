import Foundation
import CoreGraphics
import AppKit
import CoreImage

enum CatHitZone {
    case none
    case head
    case body
    case permissionPill
}

enum CatRenderer {
    private static func patterned(_ coat: CatCoatTheme) -> Bool { coat == .shorthair || coat == .orangeWhite }
    private static func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: CGFloat((hex >> 16) & 255)/255,
                green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: alpha)
    }
    private static func bodyColor(_ coat: CatCoatTheme) -> NSColor {
        coat == .shorthair ? rgb(0xC2C5C1) : (coat == .orangeWhite ? rgb(0xF2EEE4) : catBlack)
    }
    private static func limbColor(_ coat: CatCoatTheme) -> NSColor {
        coat == .orangeWhite ? rgb(0xD8AA73) : bodyColor(coat)
    }
    private static func pawColor(_ coat: CatCoatTheme) -> NSColor {
        patterned(coat) ? rgb(0xF2EEE4) : (coat == .siamese ? siamesePoint : catBlack)
    }
    private static func earTailColor(_ coat: CatCoatTheme) -> NSColor {
        coat == .siamese ? siamesePoint : limbColor(coat)
    }
    private static func creaseColor(_ coat: CatCoatTheme) -> NSColor {
        patterned(coat) ? rgb(0x8B8171, 0.60) : contourMint
    }

    static let catBlack = NSColor(calibratedRed: 0.085, green: 0.085, blue: 0.095, alpha: 1.0)
    static let contourMint = NSColor(calibratedRed: 0.82, green: 0.92, blue: 0.89, alpha: 0.76)
    static let whiskerColor = NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.92, alpha: 0.72)

    // Siamese Seal-Point Palette (挖煤小暹罗: 暖燕麦奶白躯干 + 浓郁可可焦糖重点色)
    static let siameseCream   = NSColor(calibratedRed: 0.945, green: 0.905, blue: 0.835, alpha: 1.0) // #F1E7D5
    static let siameseLatte   = NSColor(calibratedRed: 0.865, green: 0.795, blue: 0.695, alpha: 1.0) // #DDCBB1
    static let siameseMocha   = NSColor(calibratedRed: 0.45,  green: 0.34,  blue: 0.27,  alpha: 1.0) // #735745
    static let siamesePoint   = NSColor(calibratedRed: 0.175, green: 0.128, blue: 0.105, alpha: 1.0) // #2D211B
    static let siameseOutline = NSColor(calibratedRed: 0.26,  green: 0.19,  blue: 0.155, alpha: 0.88)
    static let siameseWhisker = NSColor(calibratedRed: 0.36,  green: 0.27,  blue: 0.22,  alpha: 0.68)

    static let permissionPillRect = CGRect(x: 92, y: 294, width: 176, height: 22)

    /// Hit test in 360x320 logical canvas coordinates for smart click-through & petting.
    static func hitTest(point p: CGPoint, physics: CatPhysics, showPermissionPill: Bool) -> CatHitZone {
        if showPermissionPill && CatSettings.shared.coatTheme != .customTuxedo && permissionPillRect.insetBy(dx: -4, dy: -4).contains(p) {
            return .permissionPill
        }

        if CatSettings.shared.coatTheme == .customTuxedo {
            guard DeskCatArtwork.containsInk(p,pose:physics.customDisplayedPose) else { return .none }
            if DeskCatArtwork.headRect(physics.customDisplayedPose).insetBy(dx:-3,dy:-3).contains(p) { return .head }
            return .body
        }

        let cx = CatPhysics.seatAnchor.x + physics.bodyShiftX.value
        let breath = sin(physics.time * 2.1) * 1.6
        let headCenter = CGPoint(x: cx + physics.bodyTilt.value * 42, y: 124 + physics.headOffsetY.value + breath)

        // Head hit ellipse (generous for cozy petting)
        let hdx = (p.x - headCenter.x) / 48.0
        let hdy = (p.y - headCenter.y) / 42.0
        if hdx * hdx + hdy * hdy <= 1.0 {
            return .head
        }

        // Torso + keyboard area hit check
        let bdx = (p.x - cx) / 58.0
        let bdy = (p.y - 196.0) / 56.0
        if bdx * bdx + bdy * bdy <= 1.0 {
            return .body
        }

        // Mini keyboard & mouse area (allows dragging by grabbing keyboard too)
        let kbRect = CGRect(x: 58, y: 232, width: 236, height: 64)
        if kbRect.contains(p) {
            return .body
        }

        return .none
    }

    /// Main 60fps draw routine in flipped 360x320 logical coordinate space.
    static func draw(in ctx: CGContext, physics: CatPhysics, showPermissionPill: Bool) {
        ctx.saveGState()
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        let settings = CatSettings.shared
        let coat = settings.coatTheme
        let breath = sin(physics.time * 2.1) * 1.6
        let seatX = CatPhysics.seatAnchor.x + physics.bodyShiftX.value
        let seatY = CatPhysics.seatAnchor.y

        if coat == .customTuxedo {
            drawCustomCat(in:ctx,physics:physics)
            if settings.showKeyBadges { drawFloatingKeycaps(in:ctx,physics:physics) }
            // Permission status/actions stay in the menu bar; no banner over the desktop.
            ctx.restoreGState()
            return
        }
        drawMouse(in:ctx,physics:physics,theme:settings.keyboardTheme)
        drawKeyboard(in:ctx,physics:physics,theme:settings.keyboardTheme,eyeTheme:settings.eyeTheme)

        // 3. Cat Tail (behind body)
        drawTail(in: ctx, seatX: seatX, seatY: seatY, physics: physics, coat: coat)

        // 4. 3D-Projected Ears (behind crown silhouette so Siamese seal-point ears emerge cleanly from cream skull!)
        let headCenter = CGPoint(
            x: seatX + physics.bodyTilt.value * 36 + physics.headYaw.value * 7.5,
            y: 126 + physics.headOffsetY.value + physics.headPitch.value * 4.8 + breath * 1.1
        )
        drawEarsLayer(in: ctx, center: headCenter, physics: physics, coat: coat)

        // 5. Unified C1-Continuous Head + Neck + Pear Torso Silhouette + Siamese 2.5D Face Mask
        drawUnifiedSilhouette(
            in: ctx,
            seatX: seatX,
            seatY: seatY,
            headCenter: headCenter,
            breath: breath,
            physics: physics,
            coat: coat
        )

        // 6. Hind Foot (3rd simultaneous key easter egg!)
        if physics.hindFootActive.value > 0.03 {
            drawHindFoot(in: ctx, seatX: seatX, seatY: seatY, physics: physics, coat: coat)
        }

        // 7. 2.5D Turning Head Features: Luminous Eyes & Whiskers
        drawHeadFeatures(in: ctx, center: headCenter, physics: physics, eyeTheme: settings.eyeTheme, coat: coat)

        // 8. Front Arms / Paws (over torso & keyboard/mouse with crisp separation outlines / Siamese chocolate socks!)
        drawFrontPaws(in: ctx, seatX: seatX, seatY: seatY, breath: breath, physics: physics, coat: coat)

        // 8. Floating Mechanical Keycap Badges
        if settings.showKeyBadges {
            drawFloatingKeycaps(in: ctx, physics: physics)
        }

        // 9. Subtle Petting Sparkles / Sleep Z
        drawSparkles(in: ctx, physics: physics, eyeTheme: settings.eyeTheme)

        // 10. Optional non-intrusive Permission Pill if global monitoring not yet granted
        if showPermissionPill {
            drawPermissionPill(in: ctx)
        }

        ctx.restoreGState()
    }

    // MARK: - Mini White Mouse

    private static func drawMouse(in ctx: CGContext, physics: CatPhysics, theme: KeyboardTheme) {
        let center = CGPoint(
            x: CatPhysics.mouseBaseCenter.x + physics.mouseOffset.point.x,
            y: CatPhysics.mouseBaseCenter.y + physics.mouseOffset.point.y
        )
        let pressShift = max(physics.mousePressLeft.value, physics.mousePressRight.value) * 1.6

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y + pressShift)
        ctx.rotate(by: 0.22) // angled naturally for the cat's right paw (facing the cat!)

        // Soft underside shadow
        ctx.saveGState()
        ctx.setFillColor(NSColor(calibratedWhite: 0.0, alpha: 0.24).cgColor)
        ctx.fillEllipse(in: CGRect(x: -13.5, y: -13.5 + 4.0, width: 27, height: 31))
        ctx.restoreGState()

        let bodyRect = CGRect(x: -13.5, y: -16.5, width: 27, height: 33)
        let bodyColor: NSColor
        let borderColor: NSColor
        let wheelColor: NSColor
        switch theme {
        case .classicMilk:
            bodyColor = NSColor(calibratedRed: 0.955, green: 0.950, blue: 0.925, alpha: 1.0)
            borderColor = NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.16, alpha: 1.0)
            wheelColor = NSColor(calibratedRed: 0.96, green: 0.69, blue: 0.16, alpha: 1.0)
        case .midnightHacker:
            bodyColor = NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.24, alpha: 1.0)
            borderColor = NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
            wheelColor = NSColor(calibratedRed: 0.78, green: 0.95, blue: 0.25, alpha: 1.0)
        case .retroCream:
            bodyColor = NSColor(calibratedRed: 0.89, green: 0.87, blue: 0.82, alpha: 1.0)
            borderColor = NSColor(calibratedRed: 0.20, green: 0.19, blue: 0.18, alpha: 1.0)
            wheelColor = NSColor(calibratedRed: 0.88, green: 0.42, blue: 0.24, alpha: 1.0)
        }

        // Mouse body (palm-rest dome toward cat at top, click buttons & scroll wheel away from cat at bottom!)
        ctx.setFillColor(bodyColor.cgColor)
        ctx.fillEllipse(in: bodyRect)

        // Subtle click flash highlight (cat-facing: left button = inner right side, right button = outer left side!)
        if physics.mousePressLeft.value > 0.05 {
            ctx.saveGState()
            ctx.addEllipse(in: bodyRect)
            ctx.clip()
            ctx.setFillColor(NSColor(calibratedRed: 0.79, green: 0.95, blue: 0.25, alpha: 0.38 * physics.mousePressLeft.value).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 14, height: 17))
            ctx.restoreGState()
        }
        if physics.mousePressRight.value > 0.05 {
            ctx.saveGState()
            ctx.addEllipse(in: bodyRect)
            ctx.clip()
            ctx.setFillColor(NSColor(calibratedRed: 0.79, green: 0.95, blue: 0.25, alpha: 0.38 * physics.mousePressRight.value).cgColor)
            ctx.fill(CGRect(x: -14, y: 0, width: 14, height: 17))
            ctx.restoreGState()
        }

        // Button split seam pointing forward (bottom, away from cat!)
        ctx.setStrokeColor(borderColor.withAlphaComponent(0.32).cgColor)
        ctx.setLineWidth(1.05)
        ctx.move(to: CGPoint(x: 0, y: 16))
        ctx.addLine(to: CGPoint(x: 0, y: 1.5))
        ctx.strokePath()

        // Signature amber scroll wheel on the front (bottom) half facing away from cat
        let wheelRect = CGRect(x: -1.9, y: 2.5, width: 3.8, height: 8.5)
        let wheelPath = CGPath(roundedRect: wheelRect, cornerWidth: 1.9, cornerHeight: 1.9, transform: nil)
        ctx.setFillColor(wheelColor.cgColor)
        ctx.addPath(wheelPath)
        ctx.fillPath()

        // Outer crisp outline
        ctx.setStrokeColor(borderColor.cgColor)
        ctx.setLineWidth(1.7)
        ctx.strokeEllipse(in: bodyRect)

        ctx.restoreGState()
    }

    // MARK: - Mini Angled 65% Mechanical Keyboard (facing the cat!)

    private static func drawKeyboard(
        in ctx: CGContext,
        physics: CatPhysics,
        theme: KeyboardTheme,
        eyeTheme: EyeColorTheme
    ) {
        let tl = KeyboardLayout.screenQuadPoint(su: -0.025, sv: -0.08)
        let tr = KeyboardLayout.screenQuadPoint(su: 1.025, sv: -0.08)
        let bl = KeyboardLayout.screenQuadPoint(su: -0.032, sv: 1.08)
        let br = KeyboardLayout.screenQuadPoint(su: 1.032, sv: 1.08)

        let caseDepth: CGFloat = 6.5

        // Soft ambient drop shadow beneath keyboard
        ctx.saveGState()
        let shadowPath = roundedQuadPath(
            tl: CGPoint(x: tl.x, y: tl.y + caseDepth + 2),
            tr: CGPoint(x: tr.x, y: tr.y + caseDepth + 2),
            br: CGPoint(x: br.x, y: br.y + caseDepth + 3),
            bl: CGPoint(x: bl.x, y: bl.y + caseDepth + 3),
            radius: 6
        )
        ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.22).cgColor)
        ctx.addPath(shadowPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Dark 3D chassis lower lip
        let baseColor: NSColor
        let deckColor: NSColor
        let keyColor: NSColor
        let keyBorderColor: NSColor
        let accentColor: NSColor

        switch theme {
        case .classicMilk:
            baseColor = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
            deckColor = NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.16, alpha: 1.0)
            keyColor = NSColor(calibratedRed: 0.968, green: 0.964, blue: 0.942, alpha: 1.0)
            keyBorderColor = NSColor(calibratedRed: 0.78, green: 0.77, blue: 0.74, alpha: 0.75)
            accentColor = NSColor(calibratedRed: 0.97, green: 0.70, blue: 0.16, alpha: 1.0)
        case .midnightHacker:
            baseColor = NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.08, alpha: 1.0)
            deckColor = NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0)
            keyColor = NSColor(calibratedRed: 0.21, green: 0.22, blue: 0.25, alpha: 1.0)
            keyBorderColor = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 0.95)
            accentColor = NSColor(calibratedRed: 0.77, green: 0.94, blue: 0.25, alpha: 1.0)
        case .retroCream:
            baseColor = NSColor(calibratedRed: 0.25, green: 0.24, blue: 0.22, alpha: 1.0)
            deckColor = NSColor(calibratedRed: 0.38, green: 0.36, blue: 0.33, alpha: 1.0)
            keyColor = NSColor(calibratedRed: 0.90, green: 0.88, blue: 0.82, alpha: 1.0)
            keyBorderColor = NSColor(calibratedRed: 0.68, green: 0.65, blue: 0.60, alpha: 0.85)
            accentColor = NSColor(calibratedRed: 0.88, green: 0.42, blue: 0.24, alpha: 1.0)
        }

        let lowerChassis = roundedQuadPath(
            tl: CGPoint(x: tl.x, y: tl.y + caseDepth),
            tr: CGPoint(x: tr.x, y: tr.y + caseDepth),
            br: CGPoint(x: br.x, y: br.y + caseDepth),
            bl: CGPoint(x: bl.x, y: bl.y + caseDepth),
            radius: 5.5
        )
        ctx.setFillColor(baseColor.cgColor)
        ctx.addPath(lowerChassis)
        ctx.fillPath()

        let topChassis = roundedQuadPath(tl: tl, tr: tr, br: br, bl: bl, radius: 5.0)
        ctx.setFillColor(deckColor.cgColor)
        ctx.addPath(topChassis)
        ctx.fillPath()

        // Individual keycaps — tight clean mechanical spacing matching the reference video
        let padU: CGFloat = 0.0028
        let padV: CGFloat = 0.014
        let glowBaseColor = eyeTheme.glowColor

        for cap in KeyboardLayout.keycaps {
            let glow = physics.keyGlow[cap.key] ?? 0
            // 180° rotated to face the cat: su = 1 - u, sv = 1 - v
            let su0 = (1.0 - (cap.xUnits + cap.widthUnits)) + padU
            let su1 = (1.0 - cap.xUnits) - padU
            let sv0 = (1.0 - CGFloat(cap.row + 1) / 5.0) + padV
            let sv1 = (1.0 - CGFloat(cap.row) / 5.0) - padV

            let pressDy = glow * 1.9
            let kTL = offsetY(KeyboardLayout.screenQuadPoint(su: su0, sv: sv0), pressDy)
            let kTR = offsetY(KeyboardLayout.screenQuadPoint(su: su1, sv: sv0), pressDy)
            let kBR = offsetY(KeyboardLayout.screenQuadPoint(su: su1, sv: sv1), pressDy)
            let kBL = offsetY(KeyboardLayout.screenQuadPoint(su: su0, sv: sv1), pressDy)

            let kPath = roundedQuadPath(tl: kTL, tr: kTR, br: kBR, bl: kBL, radius: 1.6)

            var fill = cap.isAmberAccent ? accentColor : keyColor
            if glow > 0.02 {
                fill = blendColor(fill, glowBaseColor, t: glow * 0.55)
            }

            ctx.setFillColor(fill.cgColor)
            ctx.addPath(kPath)
            ctx.fillPath()

            ctx.setStrokeColor(keyBorderColor.cgColor)
            ctx.setLineWidth(0.65)
            ctx.addPath(kPath)
            ctx.strokePath()
        }

        // Signature soft chartreuse backlit glow halos on active keys!
        for (key, glow) in physics.keyGlow where glow > 0.05 {
            let center = KeyboardLayout.canvasPoint(for: key)
            drawRadialGlow(
                in: ctx,
                center: center,
                radius: 17.0 + glow * 6.0,
                color: glowBaseColor.withAlphaComponent(0.36 * glow)
            )
        }
    }

    // MARK: - Tail

    private static func drawTail(in ctx: CGContext, seatX: CGFloat, seatY: CGFloat, physics: CatPhysics, coat: CatCoatTheme) {
        let p = physics.tailPhase
        let hunt = max(0, min(1, physics.huntIntensity.value))
        let wag1 = sin(p) * (8.0 + hunt * 5.5)
        let wag2 = cos(p * 1.3) * (6.0 + hunt * 4.5)
        // Tail drops lower & swishes tautly when stalking/hunting!
        let huntDrop = hunt * 14.0

        // Signature low sweep out to the right, then playful upward curl at the tip!
        let root = CGPoint(x: seatX + 34, y: seatY - 6)
        let c1 = CGPoint(x: seatX + 64, y: seatY + 2 + wag1 * 0.35 + huntDrop * 0.4)
        let c2 = CGPoint(x: seatX + 66 + wag2 * 0.4, y: seatY - 26 + wag1 * 0.7 + huntDrop)
        let tip = CGPoint(x: seatX + 91 + wag2 * 0.5, y: seatY - 30 + wag1 * 0.85 + huntDrop)

        ctx.saveGState()
        let tailColor = earTailColor(coat)
        ctx.setStrokeColor(tailColor.cgColor)
        ctx.setLineWidth(11.0)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: root)
        ctx.addCurve(to: tip, control1: c1, control2: c2)
        let tailLine = ctx.path
        ctx.strokePath()
        if patterned(coat), let line = tailLine {
            ctx.saveGState()
            ctx.addPath(line.copy(strokingWithWidth: 11, lineCap: .round, lineJoin: .round, miterLimit: 10))
            ctx.clip()
            ctx.setStrokeColor(rgb(coat == .shorthair ? 0x55595A : 0xA57543, 0.50).cgColor)
            ctx.setLineWidth(3.5); ctx.setLineCap(.butt)
            for t: CGFloat in [0.50, 0.78] {
                let u = 1-t
                let p = CGPoint(x: u*u*u*root.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*tip.x,
                                y: u*u*u*root.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*tip.y)
                let dx = 3*u*u*(c1.x-root.x)+6*u*t*(c2.x-c1.x)+3*t*t*(tip.x-c2.x)
                let dy = 3*u*u*(c1.y-root.y)+6*u*t*(c2.y-c1.y)+3*t*t*(tip.y-c2.y)
                let length = max(0.001, hypot(dx,dy)), nx = -dy/length*8, ny = dx/length*8
                ctx.move(to: CGPoint(x:p.x+nx,y:p.y+ny)); ctx.addLine(to: CGPoint(x:p.x-nx,y:p.y-ny)); ctx.strokePath()
            }
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    // MARK: - Unified C1-Continuous Cat Silhouette (Crown -> Cheeks -> Plush Neck -> Pear Hips)

    private static func drawUnifiedSilhouette(
        in ctx: CGContext,
        seatX: CGFloat,
        seatY: CGFloat,
        headCenter: CGPoint,
        breath: CGFloat,
        physics: CatPhysics,
        coat: CatCoatTheme
    ) {
        let yaw = physics.headYaw.value
        let pitch = physics.headPitch.value
        let hTilt = physics.headTilt.value
        let bTilt = physics.bodyTilt.value

        let cH = cos(hTilt), sH = sin(hTilt)
        func H(_ lx: CGFloat, _ ly: CGFloat) -> CGPoint {
            CGPoint(
                x: headCenter.x + lx * cH - ly * sH,
                y: headCenter.y + lx * sH + ly * cH
            )
        }

        let cB = cos(bTilt), sB = sin(bTilt)
        let sy = physics.bodySquash.value
        let sx = 1.0 + (1.0 - sy) * 0.55
        func B(_ lx: CGFloat, _ ly: CGFloat) -> CGPoint {
            let rx = lx * sx
            let ry = ly * sy
            return CGPoint(
                x: seatX + rx * cB - ry * sB,
                y: seatY + rx * sB + ry * cB
            )
        }

        let cheekShift = yaw * 3.0
        let crownDrop = pitch * 2.0
        let leftCheekX: CGFloat = -42.5 + cheekShift * 0.4
        let rightCheekX: CGFloat = 42.5 + cheekShift * 0.4

        // ONE single tangent-continuous closed cubic Bezier path — mathematically impossible to form any ledge or protrusion!
        let crown  = H(cheekShift * 0.2, -30 + crownDrop)
        let rCheek = H(rightCheekX, 5)
        let rHip   = B(49.0, -14)
        let rBot   = B(24.0, 12)
        let lBot   = B(-24.0, 12)
        let lHip   = B(-49.0, -14)
        let lCheek = H(leftCheekX, 5)

        let path = CGMutablePath()
        path.move(to: crown)
        path.addCurve(to: rCheek, control1: H(26 + cheekShift * 0.3, -30 + crownDrop), control2: H(rightCheekX + 1.5, -14))
        path.addCurve(to: rHip,   control1: H(rightCheekX - 2.5, 24), control2: B(51.5, -48 + breath * 0.5))
        path.addCurve(to: rBot,   control1: B(47.0, 5), control2: B(36.0, 12))
        path.addLine(to: lBot)
        path.addCurve(to: lHip,   control1: B(-36.0, 12), control2: B(-47.0, 5))
        path.addCurve(to: lCheek, control1: B(-51.5, -48 + breath * 0.5), control2: H(leftCheekX + 2.5, 24))
        path.addCurve(to: crown,  control1: H(leftCheekX - 1.5, -14), control2: H(-26 + cheekShift * 0.3, -30 + crownDrop))
        path.closeSubpath()

        ctx.saveGState()
        if coat != .siamese {
            ctx.setFillColor(bodyColor(coat).cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            if patterned(coat) {
                ctx.saveGState(); ctx.addPath(path); ctx.clip()
                drawCoatMarks(in: ctx, seatX: seatX, seatY: seatY, head: headCenter, physics: physics, coat: coat)
                ctx.restoreGState()
            }
        } else {
            // Siamese warm oat-milk cream gradient + soft toasted back shading + 2.5D rotating seal-point face mask!
            ctx.addPath(path)
            ctx.clip()

            let cs = CGColorSpaceCreateDeviceRGB()
            let bodyColors = [siameseCream.cgColor, siameseLatte.cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: bodyColors, locations: [0.15, 1.0]) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: seatX, y: headCenter.y - 34),
                    end: CGPoint(x: seatX, y: seatY + 18),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }

            // Soft toasted ear-base blend at top crown so espresso ears melt organically into cream head
            let yawRad = yaw * 0.50
            let pitchRad = pitch * 0.36
            ctx.saveGState()
            ctx.translateBy(x: headCenter.x, y: headCenter.y)
            ctx.rotate(by: hTilt)

            // 2.5D Rotating Seal-Point "挖煤" Face Mask (moves naturally across cheeks as head turns!)
            let maskCenter = projectHead3D(x: 0, y: 2.5, z: 27.0, yawRad: yawRad, pitchRad: pitchRad).pt
            let maskScaleX = max(0.76, cos(yawRad * 0.7))
            let maskScaleY = max(0.82, cos(pitchRad * 0.7))
            ctx.saveGState()
            ctx.translateBy(x: maskCenter.x, y: maskCenter.y)
            ctx.scaleBy(x: maskScaleX * 1.18, y: maskScaleY * 0.88)
            let maskColors = [
                siamesePoint.cgColor,
                siamesePoint.withAlphaComponent(0.96).cgColor,
                siameseMocha.withAlphaComponent(0.70).cgColor,
                siameseMocha.withAlphaComponent(0.0).cgColor
            ] as CFArray
            if let maskGrad = CGGradient(colorsSpace: cs, colors: maskColors, locations: [0.0, 0.44, 0.74, 1.0]) {
                ctx.drawRadialGradient(
                    maskGrad,
                    startCenter: .zero, startRadius: 2,
                    endCenter: .zero, endRadius: 31,
                    options: []
                )
            }
            ctx.restoreGState()
            ctx.restoreGState()
        }
        ctx.restoreGState()

        // Crisp subtle warm-cocoa outline around Siamese cream body so it pops on light & dark wallpapers!
        if coat == .siamese {
            ctx.saveGState()
            ctx.setStrokeColor(siameseOutline.cgColor)
            ctx.setLineWidth(1.5)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Tucked hind paws peeking softly along bottom edge
        ctx.saveGState()
        ctx.translateBy(x: seatX, y: seatY)
        ctx.rotate(by: bTilt)
        ctx.scaleBy(x: sx, y: sy)
        ctx.setFillColor(pawColor(coat).cgColor)

        ctx.fillEllipse(in: CGRect(x: -35, y: 3, width: 17, height: 11))
        if physics.hindFootActive.value < 0.35 {
            ctx.fillEllipse(in: CGRect(x: 18, y: 3, width: 17, height: 11))
        }

        // Subtle bottom rim highlights on tucked haunches
        let rimColor = (coat == .siamese) ? siameseCream.withAlphaComponent(0.55) : creaseColor(coat).withAlphaComponent(0.58)
        ctx.setStrokeColor(rimColor.cgColor)
        ctx.setLineWidth(1.3)
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: -26.5, y: 8.5), radius: 7.5, startAngle: 0.25, endAngle: .pi - 0.25, clockwise: false)
        ctx.strokePath()
        if physics.hindFootActive.value < 0.35 {
            ctx.addArc(center: CGPoint(x: 26.5, y: 8.5), radius: 7.5, startAngle: 0.25, endAngle: .pi - 0.25, clockwise: false)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private static func coatMarkPoint(_ p: CGPoint, headSurface: Bool, skull: Bool, coat: CatCoatTheme, seatX: CGFloat, seatY: CGFloat,
                                      head: CGPoint, physics: CatPhysics) -> CGPoint {
        if headSurface {
            let depth: CGFloat = coat == .orangeWhite
                ? 29.6 * sqrt(max(0, 1 - pow(p.x / 46, 2) - pow(p.y / 40, 2))) : 27.5
            let projected = skull ? p : projectHead3D(x: p.x, y: p.y, z: depth,
                                          yawRad: physics.headYaw.value * 0.50,
                                          pitchRad: physics.headPitch.value * 0.36).pt
            let c = cos(physics.headTilt.value), s = sin(physics.headTilt.value)
            return CGPoint(x: head.x + projected.x*c - projected.y*s,
                           y: head.y + projected.x*s + projected.y*c)
        }
        let sy = physics.bodySquash.value, sx = 1 + (1 - sy) * 0.55
        let c = cos(physics.bodyTilt.value), s = sin(physics.bodyTilt.value)
        return CGPoint(x: seatX + p.x*sx*c - p.y*sy*s,
                       y: seatY + p.x*sx*s + p.y*sy*c)
    }
    private static func drawCoatMarks(in ctx: CGContext, seatX: CGFloat, seatY: CGFloat,
                                      head: CGPoint, physics: CatPhysics, coat: CatCoatTheme) {
        let marks = CoatPatterns.marks(for: coat)
        func markPath(_ mark: CoatMark) -> CGMutablePath {
            let path = CGMutablePath()
            for (i, point) in mark.points.enumerated() {
                let p = coatMarkPoint(point, headSurface: mark.head, skull: mark.skull, coat: coat, seatX: seatX, seatY: seatY, head: head, physics: physics)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            if mark.width == 0 { path.closeSubpath() }
            return path
        }
        for mark in marks {
            ctx.saveGState()
            let path = markPath(mark)
            let color = rgb(mark.rgb, mark.alpha)
            if mark.width == 0 {
                path.closeSubpath(); ctx.setFillColor(color.cgColor); ctx.addPath(path); ctx.fillPath()
            } else {
                ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(mark.width)
                ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.addPath(path); ctx.strokePath()
            }
            ctx.restoreGState()
        }
    }

    // MARK: - 3rd Key Hind Foot Easter Egg

    private static func drawHindFoot(in ctx: CGContext, seatX: CGFloat, seatY: CGFloat, physics: CatPhysics, coat: CatCoatTheme) {
        let hip = CGPoint(x: seatX + 26, y: seatY + 2)
        let target = physics.hindFoot.point
        let mid = CGPoint(
            x: (hip.x + target.x) * 0.5 + 10,
            y: (hip.y + target.y) * 0.5 - 8
        )

        drawLimb(
            in: ctx,
            start: hip,
            control: mid,
            end: target,
            startWidth: 15.0,
            endWidth: 12.0,
            outlineOnLeftSide: true,
            outlineAlpha: 0.85 * physics.hindFootActive.value,
            coat: coat
        )
    }

    // MARK: - 2.5D Spherical Head Projection Helper

    /// Projects a 3D point on the cat's head ellipsoid rotated by (yawRad, pitchRad)
    /// into 2D head-local coordinates — creating true Live2D-style 2.5D head turning!
    private static func projectHead3D(
        x: CGFloat, y: CGFloat, z: CGFloat,
        yawRad: CGFloat, pitchRad: CGFloat
    ) -> (pt: CGPoint, z: CGFloat) {
        // 1. Yaw around Y axis (positive yaw = turning right toward viewer's right)
        let cy = cos(yawRad)
        let sy = sin(yawRad)
        let x1 = x * cy + z * sy
        let z1 = -x * sy + z * cy

        // 2. Pitch around X axis (positive pitch = nodding down)
        let cp = cos(pitchRad)
        let sp = sin(pitchRad)
        let y2 = y * cp + z1 * sp
        let z2 = -y * sp + z1 * cp

        return (CGPoint(x: x1, y: y2), z2)
    }

    // MARK: - 2.5D Ears Layer (drawn behind unified silhouette so Siamese seal-point ears emerge organically!)

    private static func drawEarsLayer(
        in ctx: CGContext,
        center: CGPoint,
        physics: CatPhysics,
        coat: CatCoatTheme
    ) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: physics.headTilt.value)

        let yawRad = physics.headYaw.value * 0.50
        let pitchRad = physics.headPitch.value * 0.36
        let fold = physics.earFold.value
        let twitch = physics.earTwitch.value * 0.045

        drawEar3D(in: ctx, isLeft: true, yawRad: yawRad, pitchRad: pitchRad, fold: fold, twitch: twitch, coat: coat)
        drawEar3D(in: ctx, isLeft: false, yawRad: yawRad, pitchRad: pitchRad, fold: fold, twitch: -twitch, coat: coat)

        ctx.restoreGState()
    }

    // MARK: - 2.5D Head Features (Luminous Eyes & Whiskers)

    private static func drawHeadFeatures(
        in ctx: CGContext,
        center: CGPoint,
        physics: CatPhysics,
        eyeTheme: EyeColorTheme,
        coat: CatCoatTheme
    ) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: physics.headTilt.value)

        let yaw = physics.headYaw.value      // -1 (left) .. +1 (right)
        let pitch = physics.headPitch.value  // -1 (up)   .. +1 (down)
        let yawRad = yaw * 0.50              // ~±28.5° authentic head turn
        let pitchRad = pitch * 0.36          // ~±20.5° authentic head nod

        // 1. 3D-Projected Eyes with authentic spherical foreshortening & parallax!
        drawEye3D(in: ctx, isLeft: true, yawRad: yawRad, pitchRad: pitchRad, physics: physics, eyeTheme: eyeTheme, coat: coat)
        drawEye3D(in: ctx, isLeft: false, yawRad: yawRad, pitchRad: pitchRad, physics: physics, eyeTheme: eyeTheme, coat: coat)

        // 2. 3D-Projected Whiskers (outer-side whiskers poke out past silhouette when turning!)
        drawWhiskers3D(in: ctx, yawRad: yawRad, pitchRad: pitchRad, physics: physics, coat: coat)

        ctx.restoreGState()
    }

    private static func drawEar3D(
        in ctx: CGContext,
        isLeft: Bool,
        yawRad: CGFloat,
        pitchRad: CGFloat,
        fold: CGFloat,
        twitch: CGFloat,
        coat: CatCoatTheme
    ) {
        let sign: CGFloat = isLeft ? -1.0 : 1.0
        let foldAngle = sign * (0.06 + fold * 0.34) + twitch

        let tipDx = sin(foldAngle) * 32.0
        let tipDy = -cos(foldAngle) * 32.0

        // Bases anchored comfortably inside the upper skull contour so they merge seamlessly at every yaw/pitch!
        let innerBase3D = projectHead3D(x: sign * 9.0, y: -16.0, z: 0.0, yawRad: yawRad, pitchRad: pitchRad).pt
        let outerBase3D = projectHead3D(x: sign * 35.0, y: -5.0, z: -2.0, yawRad: yawRad, pitchRad: pitchRad).pt
        let tip3D       = projectHead3D(x: sign * 24.5 + tipDx, y: -20.0 + tipDy, z: -3.0, yawRad: yawRad, pitchRad: pitchRad).pt

        // Soft plush rounded-tip feline ear
        let tipLeft  = CGPoint(x: tip3D.x - sign * 3.8, y: tip3D.y + 2.8)
        let tipRight = CGPoint(x: tip3D.x + sign * 3.8, y: tip3D.y + 3.2)

        let ear = CGMutablePath()
        ear.move(to: innerBase3D)
        ear.addQuadCurve(
            to: tipLeft,
            control: CGPoint(x: (innerBase3D.x + tipLeft.x) * 0.5 - sign * 1.5, y: (innerBase3D.y + tipLeft.y) * 0.5 - 2.0)
        )
        ear.addQuadCurve(to: tipRight, control: CGPoint(x: tip3D.x, y: tip3D.y - 2.2))
        ear.addQuadCurve(
            to: outerBase3D,
            control: CGPoint(x: (outerBase3D.x + tipRight.x) * 0.5 + sign * 2.5, y: (outerBase3D.y + tipRight.y) * 0.5 - 2.0)
        )
        ear.closeSubpath()

        ctx.saveGState()
        ctx.setFillColor(earTailColor(coat).cgColor)
        ctx.addPath(ear)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private static func drawEye3D(
        in ctx: CGContext,
        isLeft: Bool,
        yawRad: CGFloat,
        pitchRad: CGFloat,
        physics: CatPhysics,
        eyeTheme: EyeColorTheme,
        coat: CatCoatTheme
    ) {
        let sign: CGFloat = isLeft ? -1.0 : 1.0
        let eyeColor = eyeTheme.primaryColor

        // Eye sits on the front surface of the 3D head sphere at (±17.5, -2.0, +28.0)
        let proj = projectHead3D(x: sign * 17.2, y: -2.0, z: 27.5, yawRad: yawRad, pitchRad: pitchRad)

        // Authentic spherical foreshortening: the eye turning away toward the edge narrows horizontally!
        let eyeNormalAngle = yawRad + sign * 0.34
        let foreshortenX = max(0.64, min(1.06, cos(eyeNormalAngle) / cos(0.34)))
        let foreshortenY = max(0.78, min(1.03, cos(pitchRad * 0.85)))

        ctx.saveGState()
        ctx.translateBy(x: proj.pt.x, y: proj.pt.y)
        ctx.scaleBy(x: foreshortenX, y: foreshortenY)

        // Mode 1: Happy closed glowing lime-green curved line eyes (petting head!)
        if physics.isHappyClosedEyes {
            ctx.setStrokeColor(eyeColor.cgColor)
            ctx.setLineWidth(2.6)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: -11.5, y: 1.0))
            ctx.addQuadCurve(
                to: CGPoint(x: 11.5, y: 1.0),
                control: CGPoint(x: sign * 1.5, y: 3.4)
            )
            ctx.strokePath()
            ctx.restoreGState()
            return
        }

        // Mode 2: Blissful half-squint glowing lime slits (petting back/body!)
        if physics.isBlissfulSquint {
            ctx.setFillColor(eyeColor.cgColor)
            let slit = CGMutablePath()
            slit.move(to: CGPoint(x: -11.5, y: -0.5))
            slit.addQuadCurve(to: CGPoint(x: 11.5, y: -0.5), control: CGPoint(x: 0, y: 0.6))
            slit.addQuadCurve(to: CGPoint(x: -11.5, y: -0.5), control: CGPoint(x: 0, y: 4.8))
            slit.closeSubpath()
            ctx.addPath(slit)
            ctx.fillPath()
            ctx.restoreGState()
            return
        }

        let hunt = max(0, min(1, physics.huntIntensity.value))

        // Subtle feline eye angle (straightens slightly when wide-eyed hunting!)
        ctx.rotate(by: sign * (0.06 * (1.0 - hunt * 0.6)))

        // Eyes grow rounder & slightly larger in full hunting focus!
        let rx: CGFloat = 12.0 + hunt * 1.1
        let ry: CGFloat = 10.8 + hunt * 1.8
        let eyeRect = CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)

        // Clip to the visible opening before painting any iris/pupil pixels.
        // Painting a lid over an antialiased oval leaves a colored fringe.
        ctx.saveGState()
        ctx.addEllipse(in: eyeRect)
        ctx.clip()

        let closure = max(0, min(1, physics.effectiveEyeClosure))
        if closure >= 1 {
            ctx.restoreGState()
            ctx.restoreGState()
            return
        }
        if closure > 0 {
            ctx.clip(to: CGRect(x: -rx - 2, y: -ry + 2 * ry * closure,
                                width: 2 * rx + 4, height: 2 * ry * (1 - closure)))
        }

        // Luminous chartreuse iris
        ctx.setFillColor(eyeColor.cgColor)
        ctx.fill(eyeRect)

        // Pupil morphs smoothly from vertical almond slit -> HUGE round black boba pupil when hunting!
        let gaze = physics.eyeGaze.point
        let px = gaze.x * (4.2 - hunt * 1.2)
        let py = gaze.y * (3.6 - hunt * 1.0)
        let pScale = physics.pupilScale.value
        let normalW: CGFloat = 5.0 * pScale
        let normalH: CGFloat = 13.5 * min(1.12, pScale)
        let huntDiameter: CGFloat = 18.8 // huge round boba pupil leaving an electric chartreuse ring!
        let pupilW = normalW + (huntDiameter - normalW) * hunt
        let pupilH = normalH + (huntDiameter - normalH) * hunt
        let pupilRect = CGRect(x: px - pupilW * 0.5, y: py - pupilH * 0.5, width: pupilW, height: pupilH)
        // Photo-sampled hazel: #DAB257 outside, a narrow #8D9180 ring by the pupil.
        // Paint inside the existing lid clip and follow the animated pupil position/size.
        if eyeTheme == .referenceHazel {
            for i in 0...24 {
                let t = CGFloat(i) / 24
                let mix = t * t * (3 - 2 * t)
                ctx.setFillColor(NSColor(calibratedRed: (218 - 77 * mix)/255,
                    green: (178 - 33 * mix)/255, blue: (87 + 41 * mix)/255, alpha: 1).cgColor)
                let rim = (1 - t) * 2.2
                ctx.fillEllipse(in: pupilRect.insetBy(dx: -rim, dy: -rim))
            }
        }
        ctx.setFillColor(catBlack.cgColor)
        ctx.fillEllipse(in: pupilRect)

        // Tiny crisp white specular sparkle dot as hunting boba pupils dilate!
        if hunt > 0.25 {
            let glintAlpha = min(1.0, (hunt - 0.25) / 0.55) * 0.92
            ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: glintAlpha).cgColor)
            let glintR: CGFloat = 2.1 + hunt * 0.9
            ctx.fillEllipse(in: CGRect(
                x: px - pupilW * 0.22 - glintR * 0.5,
                y: py - pupilH * 0.22 - glintR * 0.5,
                width: glintR * 2,
                height: glintR * 2
            ))
        }

        ctx.restoreGState()
        ctx.restoreGState()
    }

    private static func drawWhiskers3D(
        in ctx: CGContext,
        yawRad: CGFloat,
        pitchRad: CGFloat,
        physics: CatPhysics,
        coat: CatCoatTheme
    ) {
        let wiggle = sin(physics.time * 4.5) * (max(physics.petHeadIntensity, physics.petBodyIntensity) * 1.2)
        ctx.saveGState()
        let wColor = (coat == .siamese) ? siameseWhisker : (patterned(coat) ? rgb(0x8D8170) : whiskerColor).withAlphaComponent(0.68)
        ctx.setStrokeColor(wColor.cgColor)
        ctx.setLineWidth(1.0)
        ctx.setLineCap(.round)

        // 3D cheek whiskers — when turning left, left whiskers naturally poke past silhouette
        // while right whiskers sweep inward across the cheek (exact Xiaohongshu effect!)
        for sign in [-1.0, 1.0] as [CGFloat] {
            let rows: [(CGFloat, CGFloat, CGFloat)] = [
                (10.5, 36.5, 8.8 + wiggle),
                (14.2, 37.8, 14.2 + wiggle * 0.5),
                (18.0, 35.5, 19.6 - wiggle * 0.4)
            ]
            for (y0, xEnd, yEnd) in rows {
                let p0 = projectHead3D(x: sign * 24.0, y: y0, z: 23.0, yawRad: yawRad, pitchRad: pitchRad).pt
                let p2 = projectHead3D(x: sign * xEnd, y: yEnd, z: 14.0, yawRad: yawRad, pitchRad: pitchRad).pt
                let ctrl = CGPoint(x: (p0.x + p2.x) * 0.5, y: (p0.y + p2.y) * 0.5 - 0.8)
                ctx.move(to: p0)
                ctx.addQuadCurve(to: p2, control: ctrl)
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Front Paws (Idle Sitting & Dynamic Reaching with Signature Outlines / Siamese Socks)

    private static func drawFrontPaws(
        in ctx: CGContext,
        seatX: CGFloat,
        seatY: CGFloat,
        breath: CGFloat,
        physics: CatPhysics,
        coat: CatCoatTheme
    ) {
        let lPos = physics.leftPaw.point
        let rPos = physics.rightPaw.point

        let lDist = hypot(lPos.x - CatPhysics.leftPawRest.x, lPos.y - CatPhysics.leftPawRest.y)
        let rDist = hypot(rPos.x - CatPhysics.rightPawRest.x, rPos.y - CatPhysics.rightPawRest.y)

        // Attach to the transformed chest, below the moving face rather than its white blaze.
        func shoulder(_ x: CGFloat) -> CGPoint {
            let sy = physics.bodySquash.value, sx = 1 + (1 - sy) * 0.55
            let c = cos(physics.bodyTilt.value), s = sin(physics.bodyTilt.value)
            let faceBottom = 126 + physics.headOffsetY.value + physics.headPitch.value * 4.8 + breath * 1.1 + 52
            return CGPoint(x: seatX + x*sx*c + 43*sy*s,
                           y: max(seatY + x*sx*s - 43*sy*c, faceBottom))
        }
        let leftShoulder = shoulder(-20)
        let rightShoulder = shoulder(20)

        // Left arm
        if lDist < 6.0 && !physics.leftPawOnMouse && !physics.leftPawTyping {
            drawIdleFrontLeg(in: ctx, top: CGPoint(x: seatX - 18, y: seatY - 30), bottom: CGPoint(x: seatX - 16, y: seatY + 12), isLeft: true, coat: coat)
        } else {
            let mid = CGPoint(
                x: (leftShoulder.x + lPos.x) * 0.5 - (physics.leftPawOnMouse ? 8 : 4),
                y: (leftShoulder.y + lPos.y) * 0.5 - 6
            )
            drawLimb(
                in: ctx,
                start: leftShoulder,
                control: mid,
                end: lPos,
                startWidth: 19.0,
                endWidth: 13.5,
                outlineOnLeftSide: false,
                outlineAlpha: 0.78,
                coat: coat
            )
        }

        // Right arm
        if rDist < 6.0 && !physics.rightPawTyping {
            drawIdleFrontLeg(in: ctx, top: CGPoint(x: seatX + 18, y: seatY - 30), bottom: CGPoint(x: seatX + 16, y: seatY + 12), isLeft: false, coat: coat)
        } else {
            let mid = CGPoint(
                x: (rightShoulder.x + rPos.x) * 0.5 + 4,
                y: (rightShoulder.y + rPos.y) * 0.5 - 6
            )
            drawLimb(
                in: ctx,
                start: rightShoulder,
                control: mid,
                end: rPos,
                startWidth: 19.0,
                endWidth: 13.5,
                outlineOnLeftSide: true,
                outlineAlpha: 0.78,
                coat: coat
            )
        }
    }

    /// Signature tucked sitting front legs (black with mint lines OR Siamese cream-to-chocolate socks!)
    private static func drawIdleFrontLeg(in ctx: CGContext, top: CGPoint, bottom: CGPoint, isLeft: Bool, coat: CatCoatTheme) {
        let sign: CGFloat = isLeft ? -1.0 : 1.0
        ctx.saveGState()

        if coat == .siamese {
            // Creamy upper leg dipping smoothly into adorable seal-point chocolate socks at the bottom!
            let legRect = CGRect(x: bottom.x - 7.5, y: top.y, width: 15.0, height: bottom.y - top.y + 1.0)
            let legPath = CGPath(roundedRect: legRect, cornerWidth: 6.5, cornerHeight: 6.5, transform: nil)
            ctx.saveGState()
            ctx.addPath(legPath)
            ctx.clip()
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [
                siameseCream.withAlphaComponent(0.0).cgColor,
                siameseMocha.withAlphaComponent(0.75).cgColor,
                siamesePoint.cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0.05, 0.52, 0.85]) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: top.x, y: top.y),
                    end: CGPoint(x: bottom.x, y: bottom.y + 2),
                    options: []
                )
            }
            ctx.restoreGState()
        }

        if patterned(coat) {
            ctx.setFillColor(pawColor(coat).cgColor)
            let cuff = CGRect(x: bottom.x - 7.5, y: bottom.y - 13, width: 15, height: 18)
            ctx.addPath(CGPath(roundedRect: cuff, cornerWidth: 6.5, cornerHeight: 6.5, transform: nil))
            ctx.fillPath()
        }
        let lineColor = (coat == .siamese) ? siameseOutline.withAlphaComponent(0.62) : creaseColor(coat)
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(1.45)
        ctx.setLineCap(.round)

        // Outer separation crease
        ctx.move(to: CGPoint(x: top.x + sign * 8.5, y: top.y))
        ctx.addQuadCurve(
            to: CGPoint(x: bottom.x + sign * 7.5, y: bottom.y - 1),
            control: CGPoint(x: top.x + sign * 9.5, y: (top.y + bottom.y) * 0.5)
        )
        // Inner separation crease
        ctx.move(to: CGPoint(x: top.x - sign * 7.0, y: top.y + 4))
        ctx.addQuadCurve(
            to: CGPoint(x: bottom.x - sign * 6.0, y: bottom.y - 1),
            control: CGPoint(x: top.x - sign * 6.5, y: (top.y + bottom.y) * 0.5)
        )
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Smooth tapered limb + plump rounded paw (matte black OR Siamese cream-to-espresso chocolate socks!)
    private static func drawLimb(
        in ctx: CGContext,
        start: CGPoint,
        control: CGPoint,
        end: CGPoint,
        startWidth: CGFloat,
        endWidth: CGFloat,
        outlineOnLeftSide: Bool,
        outlineAlpha: CGFloat,
        coat: CatCoatTheme
    ) {
        let steps = 14
        var leftEdge: [CGPoint] = []
        var rightEdge: [CGPoint] = []

        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = quadPoint(start, control, end, t: t)
            let tan = quadTangent(start, control, end, t: t)
            let len = max(0.001, hypot(tan.x, tan.y))
            let nx = -tan.y / len
            let ny = tan.x / len
            let halfW = (startWidth + (endWidth - startWidth) * t) * 0.5
            leftEdge.append(CGPoint(x: p.x + nx * halfW, y: p.y + ny * halfW))
            rightEdge.append(CGPoint(x: p.x - nx * halfW, y: p.y - ny * halfW))
        }

        let limbPath = CGMutablePath()
        limbPath.move(to: leftEdge[0])
        for pt in leftEdge.dropFirst() { limbPath.addLine(to: pt) }
        for pt in rightEdge.reversed() { limbPath.addLine(to: pt) }
        let tangent = quadTangent(start, control, end, t: 0)
        let length = max(0.001, hypot(tangent.x, tangent.y))
        limbPath.addQuadCurve(to: leftEdge[0], control: CGPoint(
            x: start.x - tangent.x/length*startWidth*0.5,
            y: start.y - tangent.y/length*startWidth*0.5))
        limbPath.closeSubpath()

        let pawR = endWidth * 0.58
        let pawRect = CGRect(x: end.x - pawR, y: end.y - pawR * 0.85, width: pawR * 2, height: pawR * 1.7)

        ctx.saveGState()
        if coat != .siamese {
            ctx.setFillColor(limbColor(coat).cgColor)
            ctx.addPath(limbPath)
            if patterned(coat) {
                ctx.saveGState(); ctx.clip()
                let colors = [pawColor(coat).cgColor, limbColor(coat).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.30]) {
                    ctx.drawLinearGradient(gradient, start: start, end: end,
                                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
                ctx.restoreGState()
            } else { ctx.fillPath() }
            if !patterned(coat) { ctx.fillEllipse(in: pawRect) }
            if patterned(coat) {
                let cuff = CGMutablePath()
                let first = Int(CGFloat(steps) * 0.72)
                cuff.move(to: leftEdge[first])
                for pt in leftEdge.dropFirst(first + 1) { cuff.addLine(to: pt) }
                for pt in rightEdge.dropFirst(first).reversed() { cuff.addLine(to: pt) }
                cuff.closeSubpath()
                ctx.setFillColor(pawColor(coat).cgColor); ctx.addPath(cuff); ctx.fillPath()
                ctx.fillEllipse(in: pawRect)
            }
        } else {
            // Siamese chocolate-dipped socks gradient along the limb!
            // Starts transparent at shoulder (0.0) so it melts 100% seamlessly into the creamy chest!
            ctx.saveGState()
            ctx.addPath(limbPath)
            ctx.clip()
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [
                siameseCream.withAlphaComponent(0.0).cgColor,
                siameseCream.cgColor,
                siameseMocha.cgColor,
                siamesePoint.cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0.0, 0.16, 0.48, 0.78]) {
                ctx.drawLinearGradient(grad, start: start, end: end, options: [.drawsAfterEndLocation])
            }
            ctx.restoreGState()

            // Solid rich espresso-chocolate rounded paw tip (no winding-rule overlap artifacts!)
            ctx.setFillColor(siamesePoint.cgColor)
            ctx.fillEllipse(in: pawRect)

            // Clean outer edge outline on Siamese arm (fading in below shoulder) so it reads crisply over light backgrounds
            ctx.setStrokeColor(siameseOutline.withAlphaComponent(0.72).cgColor)
            ctx.setLineWidth(1.25)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let outerEdge = outlineOnLeftSide ? rightEdge : leftEdge
            if outerEdge.count > 4 {
                ctx.move(to: outerEdge[3])
                for idx in 4..<(outerEdge.count - 1) { ctx.addLine(to: outerEdge[idx]) }
                ctx.strokePath()
            }
        }

        // Crisp separation stroke along upper-to-mid arm where it crosses the torso
        let highlightEdge = outlineOnLeftSide ? leftEdge : rightEdge
        if highlightEdge.count > 6 {
            let strokeColor = (coat == .siamese)
                ? siameseOutline.withAlphaComponent(outlineAlpha * 0.78)
                : creaseColor(coat).withAlphaComponent(outlineAlpha * 0.9)
            ctx.setStrokeColor(strokeColor.cgColor)
            ctx.setLineWidth(1.35)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let startIdx = 2
            let endIdx = Int(CGFloat(highlightEdge.count - 1) * 0.68)
            ctx.move(to: highlightEdge[startIdx])
            for idx in (startIdx + 1)...endIdx {
                ctx.addLine(to: highlightEdge[idx])
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: - Floating Mechanical Keycap Popups

    private static func drawFloatingKeycaps(in ctx: CGContext, physics: CatPhysics) {
        let desk=CatSettings.shared.coatTheme == .customTuxedo
        for badge in physics.floatingKeycaps {
            let progress = badge.age / badge.lifetime
            // Spring pop-in scale (starts crisp and readable immediately!)
            let scale: CGFloat
            if badge.age < 0.09 {
                let t = badge.age / 0.09
                scale = 0.72 + 0.38 * sin(t * .pi * 0.65)
            } else if badge.age < 0.18 {
                let t = (badge.age - 0.09) / 0.09
                scale = 1.10 - 0.10 * t
            } else {
                scale = 1.0
            }

            let alpha: CGFloat = progress < 0.62 ? 1.0 : max(0, 1.0 - (progress - 0.62) / 0.38)

            let charCount = badge.label.count
            let w: CGFloat = max(23,min(90,CGFloat(charCount)*7.0+14))
            let h: CGFloat = 22

            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.translateBy(x: badge.position.x, y: badge.position.y)
            ctx.rotate(by: badge.rotation)
            ctx.scaleBy(x: scale, y: scale)

            // 3D bottom keycap edge / shadow
            let baseRect = CGRect(x: -w * 0.5, y: -h * 0.5 + 2.5, width: w, height: h)
            let basePath = CGPath(roundedRect: baseRect, cornerWidth: 5.5, cornerHeight: 5.5, transform: nil)
            ctx.setFillColor((desk ? rgb(0xCDB38E) : NSColor(calibratedRed:0.15,green:0.15,blue:0.17,alpha:0.95)).cgColor)
            ctx.addPath(basePath)
            ctx.fillPath()

            // Crisp white mechanical keycap top face
            let faceRect = CGRect(x: -w * 0.5, y: -h * 0.5, width: w, height: h)
            let facePath = CGPath(roundedRect: faceRect, cornerWidth: 5.2, cornerHeight: 5.2, transform: nil)
            ctx.setFillColor((desk ? rgb(0xFFF8E9) : NSColor(calibratedRed:0.975,green:0.972,blue:0.952,alpha:1)).cgColor)
            ctx.addPath(facePath)
            ctx.fillPath()

            ctx.setStrokeColor((desk ? rgb(0x786044) : NSColor(calibratedRed:0.16,green:0.16,blue:0.18,alpha:1)).cgColor)
            ctx.setLineWidth(1.45)
            ctx.addPath(facePath)
            ctx.strokePath()

            // Centered bold key label
            let fontSize: CGFloat = charCount <= 1 ? 11.5 : 10.0
            let font = NSFont.systemFont(ofSize: fontSize, weight:desk ? .medium : .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: desk ? rgb(0x594A36) : NSColor(calibratedRed:0.12,green:0.12,blue:0.14,alpha:1)
            ]
            let attrStr = NSAttributedString(string: badge.label, attributes: attrs)
            let strSize = attrStr.size()
            let drawPt = CGPoint(x: -strSize.width * 0.5, y: -strSize.height * 0.5 - 0.5)
            NSGraphicsContext.saveGraphicsState()
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.current = nsCtx
            attrStr.draw(at: drawPt)
            NSGraphicsContext.restoreGraphicsState()

            ctx.restoreGState()
        }
    }

    // MARK: - Subtle Petting Sparkles & Sleep Z

    private static func drawSparkles(in ctx: CGContext, physics: CatPhysics, eyeTheme: EyeColorTheme) {
        for sp in physics.sparkles {
            let p = sp.age / sp.lifetime
            let alpha = sin(min(1.0, p) * .pi)
            ctx.saveGState()
            ctx.setAlpha(alpha * 0.85)
            if sp.isSleepZ {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11 + p * 3, weight: .bold),
                    .foregroundColor: eyeTheme.primaryColor
                ]
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                NSAttributedString(string: "z", attributes: attrs).draw(at: sp.position)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                // Tiny glowing chartreuse 4-point star
                let r: CGFloat = 3.5 + p * 1.5
                ctx.translateBy(x: sp.position.x, y: sp.position.y)
                ctx.setFillColor(eyeTheme.primaryColor.cgColor)
                let star = CGMutablePath()
                star.move(to: CGPoint(x: 0, y: -r))
                star.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0.8, y: -0.8))
                star.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: 0.8, y: 0.8))
                star.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -0.8, y: 0.8))
                star.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: -0.8, y: -0.8))
                star.closeSubpath()
                ctx.addPath(star)
                ctx.fillPath()
            }
            ctx.restoreGState()
        }
    }

    // MARK: - Non-Intrusive Permission Pill

    private static func drawPermissionPill(in ctx: CGContext) {
        let r = permissionPillRect
        let path = CGPath(roundedRect: r, cornerWidth: 11, cornerHeight: 11, transform: nil)

        ctx.saveGState()
        ctx.setFillColor(NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 0.90).cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setStrokeColor(NSColor(calibratedRed: 0.79, green: 0.95, blue: 0.25, alpha: 0.90).cgColor)
        ctx.setLineWidth(1.2)
        ctx.addPath(path)
        ctx.strokePath()

        let text = "点击开启全局/游戏键盘监听 🔑"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.95, green: 0.97, blue: 0.90, alpha: 1.0)
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let sz = str.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        str.draw(at: CGPoint(x: r.midX - sz.width * 0.5, y: r.midY - sz.height * 0.5 - 0.5))
        NSGraphicsContext.restoreGraphicsState()

        ctx.restoreGState()
    }

    // MARK: - Geometry & Color Helpers

    private static func offsetY(_ pt: CGPoint, _ dy: CGFloat) -> CGPoint {
        CGPoint(x: pt.x, y: pt.y + dy)
    }

    private static func quadPoint(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x,
            y: mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y
        )
    }

    private static func quadTangent(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: 2 * mt * (p1.x - p0.x) + 2 * t * (p2.x - p1.x),
            y: 2 * mt * (p1.y - p0.y) + 2 * t * (p2.y - p1.y)
        )
    }

    private static func roundedQuadPath(
        tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint, radius: CGFloat
    ) -> CGPath {
        let p = CGMutablePath()
        let midTop = CGPoint(x: (tl.x + tr.x) * 0.5, y: (tl.y + tr.y) * 0.5)
        p.move(to: midTop)
        p.addArc(tangent1End: tr, tangent2End: br, radius: radius)
        p.addArc(tangent1End: br, tangent2End: bl, radius: radius)
        p.addArc(tangent1End: bl, tangent2End: tl, radius: radius)
        p.addArc(tangent1End: tl, tangent2End: tr, radius: radius)
        p.closeSubpath()
        return p
    }

    private static func blendColor(_ a: NSColor, _ b: NSColor, t: CGFloat) -> NSColor {
        let ca = a.usingColorSpace(.deviceRGB) ?? a
        let cb = b.usingColorSpace(.deviceRGB) ?? b
        let clamped = max(0, min(1, t))
        return NSColor(
            calibratedRed: ca.redComponent + (cb.redComponent - ca.redComponent) * clamped,
            green: ca.greenComponent + (cb.greenComponent - ca.greenComponent) * clamped,
            blue: ca.blueComponent + (cb.blueComponent - ca.blueComponent) * clamped,
            alpha: ca.alphaComponent + (cb.alphaComponent - ca.alphaComponent) * clamped
        )
    }

    private static func drawRadialGlow(in ctx: CGContext, center: CGPoint, radius: CGFloat, color: NSColor) {
        let cs = CGColorSpaceCreateDeviceRGB()
        let colors = [color.cgColor, color.withAlphaComponent(0.0).cgColor] as CFArray
        let locs: [CGFloat] = [0.0, 1.0]
        if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: locs) {
            ctx.saveGState()
            ctx.drawRadialGradient(
                grad,
                startCenter: center, startRadius: 0,
                endCenter: center, endRadius: radius,
                options: []
            )
            ctx.restoreGState()
        }
    }
    // MARK: - Approved illustrated poses and isolated idle animation layers
    private static func drawCustomCat(in ctx: CGContext, physics p: CatPhysics) {
        let id=p.customDisplayedPose
        guard let image=DeskCatArtwork.animatedImage(id,physics:p) else { return }
        let rect=DeskCatArtwork.rect
        ctx.saveGState();ctx.setAlpha(p.customPoseOpacity);ctx.interpolationQuality = .high
        ctx.translateBy(x:rect.minX,y:rect.maxY);ctx.scaleBy(x:1,y:-1)
        ctx.draw(image,in:CGRect(origin:.zero,size:rect.size))
        ctx.restoreGState()
    }
}

/// The exact approved masters are packaged with the app. Crop rectangles come from their manifest.
/// Images are decoded and cropped once; the 60 FPS render loop only transforms cached CGImages.
enum CustomCatArtwork {
    static let images:[String:CGImage] = {
        let folder:URL
        if let path=ProcessInfo.processInfo.environment["KUROCAT_ARTWORK_DIR"] {
            folder=URL(fileURLWithPath:path)
        } else {
            folder=Bundle.main.resourceURL!.appendingPathComponent("CustomCat")
        }
        guard let data=try? Data(contentsOf:folder.appendingPathComponent("manifest.json")),
              let manifest=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let atlases=manifest["atlases"] as? [[String:Any]] else { return [:] }
        var result:[String:CGImage]=[:]
        for atlas in atlases {
            guard let filename=atlas["file"] as? String,
                  let frames=atlas["frames"] as? [[String:Any]],
                  let source=NSImage(contentsOf:folder.appendingPathComponent(filename)),
                  let image=source.cgImage(forProposedRect:nil,context:nil,hints:nil) else { continue }
            for frame in frames {
                guard let id=frame["id"] as? String,
                      let cell=frame["extraction_rect_xywh"] as? [Int],cell.count == 4,
                      let box=frame["content_bbox_in_frame_alpha_gt_32"] as? [Int],box.count == 4 else { continue }
                // Keep the original antialiasing and a small transparent margin around the ink.
                let rect=CGRect(x:cell[0]+box[0]-3,y:cell[1]+box[1]-3,
                                width:box[2]-box[0]+6,height:box[3]-box[1]+6)
                result[id]=image.cropping(to:rect)
            }
        }
        return result
    }()
}


extension CustomCatArtwork {
    static func poseRect(_ id:String) -> CGRect {
        guard let image=images[id] else { return .zero }
        let scale:CGFloat = id == "belly_hug" ? 0.50 : 0.54
        let width=CGFloat(image.width)*scale,height=CGFloat(image.height)*scale
        return CGRect(x:184-width/2,y:258-height,width:width,height:height)
    }

    static func headRect(_ id:String) -> CGRect {
        switch id {
        case "rest_side": return CGRect(x:0.56,y:0.03,width:0.42,height:0.82)
        case "belly_hug": return CGRect(x:0.32,y:0,width:0.64,height:0.42)
        case "groom_leg": return CGRect(x:0.17,y:0.25,width:0.52,height:0.47)
        default: return CGRect(x:0.19,y:0,width:0.63,height:0.45)
        }
    }

    private static let ciContext=CIContext(options:[.cacheIntermediates:false])
    private static let ciImages=images.mapValues { CIImage(cgImage:$0) }
    // Only the eye patches change for blinking. Use the supplied eyelid ink, not a second head.
    private static let closedSit:CIImage? = {
        guard let original=images["sit_base"],let lids=images["eyes_closed_overlay"],
              let context=CGContext(data:nil,width:original.width,height:original.height,
                                    bitsPerComponent:8,bytesPerRow:original.width*4,
                                    space:CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(original,in:CGRect(x:0,y:0,width:original.width,height:original.height))
        context.translateBy(x:0,y:CGFloat(original.height));context.scaleBy(x:1,y:-1)
        for (i,x) in [CGFloat(77.5),CGFloat(131.5)].enumerated() {
            let color=i == 0 ? NSColor(calibratedRed:31/255.0,green:27/255.0,blue:25/255.0,alpha:1)
                             : NSColor(calibratedRed:34/255.0,green:30/255.0,blue:28/255.0,alpha:1)
            context.setFillColor(color.cgColor)
            context.fillEllipse(in:CGRect(x:x-14,y:67,width:28,height:27))
            guard let lid=lids.cropping(to:CGRect(x:i*lids.width/2,y:0,width:lids.width/2,height:lids.height)) else { continue }
            context.saveGState();context.translateBy(x:x-13,y:86);context.scaleBy(x:1,y:-1)
            context.draw(lid,in:CGRect(x:0,y:0,width:26,height:7.5));context.restoreGState()
        }
        return context.makeImage().map { CIImage(cgImage:$0) }
    }()
    // A smooth displacement field maps every pixel of the SAME full-body image.
    // Its Gaussian falloff carries joints/neck/markings together and fixes the contact paws.
    private static let motionKernel=CIWarpKernel(source:"""
        kernel vec2 connectedMotion(vec2 size, vec4 motion, vec4 detail, float pose) {
            vec2 pixel=destCoord();
            vec2 uv=vec2(pixel.x/size.x,1.0-pixel.y/size.y);
            vec2 d=vec2(0.0);
            vec2 chest=(uv-vec2(0.5,0.64))/vec2(0.32,0.24);
            float breathe=exp(-dot(chest,chest));
            d.y += motion.x*breathe;
            d.x += motion.x*(uv.x-0.5)*breathe*0.65;
            if (pose < 0.5) {
                float upper=1.0-smoothstep(0.28,0.67,uv.y);
                d.x += motion.y*upper;
                vec2 l=(uv-vec2(0.35,0.92))/vec2(0.09,0.12);
                vec2 r=(uv-vec2(0.55,0.92))/vec2(0.09,0.12);
                d.y += motion.z*exp(-dot(l,l))+motion.w*exp(-dot(r,r));

            }
            if (pose > 1.5 && pose < 2.5) {
                vec2 l=(uv-vec2(0.32,0.39))/vec2(0.16,0.15);
                vec2 r=(uv-vec2(0.73,0.40))/vec2(0.15,0.15);
                d.x += detail.y*(exp(-dot(l,l))-exp(-dot(r,r)));
            }
            if (pose > 2.5) {
                vec2 paw=(uv-vec2(0.24,0.17))/vec2(0.25,0.22);
                float leg=exp(-dot(paw,paw));
                d.x += detail.y*leg;
                d.y += detail.z*leg;
            }
            vec2 tail=(uv-vec2(0.79,0.91))/vec2(0.20,0.075);
            d.x += detail.w*exp(-dot(tail,tail));
            return pixel+vec2(d.x,-d.y);
        }
        """)

    static func animatedImage(_ id:String,physics p:CatPhysics) -> CGImage? {
        guard let original=images[id],let open=ciImages[id],let kernel=motionKernel else { return images[id] }
        let input = id == "sit_base" && p.effectiveEyeClosure > 0.55 ? (closedSit ?? open) : open
        let scale:CGFloat = id == "belly_hug" ? 0.50 : 0.54
        let t=p.time
        let pose:CGFloat = id == "sit_base" ? 0 : (id == "rest_side" ? 1 : (id == "belly_hug" ? 2 : 3))
        // At desktop size all offsets remain below three points, with no long reaching arms.
        let breath=sin(t*(pose == 1 ? 1.65 : 2.0))*(pose == 1 ? 0.45 : 0.7)/scale
        let left=p.leftPawTyping ? max(-2.5,min(2.5,(235-p.leftPaw.point.y)*0.14))/scale : 0
        let right=p.rightPawTyping ? max(-2.5,min(2.5,(235-p.rightPaw.point.y)*0.14))/scale : 0
        let motion=CIVector(x:breath,y:max(-1,min(1,p.headYaw.value))*1.5/scale,z:left,w:right)
        let detail=CIVector(x:min(0.97,p.effectiveEyeClosure),
                            y:sin(t*2.5)*(pose == 3 ? 2.0 : 0.6)/scale,
                            z:cos(t*2.5)*0.8/scale,w:sin(p.tailPhase)*0.8/scale)
        let extent=input.extent
        guard let warped=kernel.apply(extent:extent,roiCallback:{ _,rect in rect.insetBy(dx:-24,dy:-24) },
              image:input,arguments:[CIVector(x:CGFloat(original.width),y:CGFloat(original.height)),motion,detail,pose]),
              let output=ciContext.createCGImage(warped,from:extent) else { return original }
        return output
    }
}

/// Approved desk scene, with one continuous texture and rigid paw cores.
/// Offsets use the original 512px vignette coordinates; body/head never follow the cursor.
enum DeskCatArtwork {
    static let rect = CGRect(x:12,y:0,width:336,height:301.875)
    static let scale:CGFloat = 336/512
    static func canvas(_ p:CGPoint)->CGPoint {
        CGPoint(x:rect.minX+p.x*scale,y:rect.minY+(p.y-40)*scale)
    }
    static let eyeOrigin = canvas(CGPoint(x:280,y:175))
    static let sceneIDs = ["sit_base","wave","rest_side","belly_hug","groom_leg","observe"]
    static let images:[String:CGImage] = {
        let folder:URL
        if let path=ProcessInfo.processInfo.environment["KUROCAT_ARTWORK_DIR"] { folder=URL(fileURLWithPath:path) }
        else { folder=Bundle.main.resourceURL!.appendingPathComponent("CustomCat") }
        guard let src=NSImage(contentsOf:folder.appendingPathComponent("desk-minimal.png")),
              let full=src.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return [:] }
        var result:[String:CGImage]=[:]
        for (i,id) in sceneIDs.enumerated() {
            result[id]=full.cropping(to:CGRect(x:(i%3)*512,y:(i/3)*512+40,width:512,height:460))
        }
        return result
    }()
    // Transparent desktop area must remain click-through, even inside the sprite canvas.
    private static let alphaMasks:[String:[UInt8]] = images.mapValues { image in
        let c=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,
                        bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        let bytes=c.data!.assumingMemoryBound(to:UInt8.self)
        return (0..<(image.width*image.height)).map { bytes[$0*4+3] }
    }
    static func containsInk(_ point:CGPoint,pose:String)->Bool {
        guard rect.contains(point),let image=images[pose],let mask=alphaMasks[pose] else { return false }
        let x=Int((point.x-rect.minX)/rect.width*CGFloat(image.width))
        let y=Int((point.y-rect.minY)/rect.height*CGFloat(image.height))
        guard x>=0 && x<image.width && y>=0 && y<image.height else { return false }
        return mask[y*image.width+x]>48
    }
    static func keyPoint(_ key:PhysicalKey)->CGPoint {
        let uv=KeyboardLayout.lookup[key.visualKey]?.normalizedCenter ?? CGPoint(x:0.5,y:0.5)
        return canvas(CGPoint(x:160+uv.x*144,y:360+uv.y*31))
    }
    static func headRect(_ id:String)->CGRect {
        let b:CGRect
        switch id {
        case "rest_side": b=CGRect(x:244,y:182,width:184,height:195)
        case "belly_hug": b=CGRect(x:233,y:64,width:184,height:178)
        case "groom_leg": b=CGRect(x:122,y:201,width:167,height:132)
        case "wave": b=CGRect(x:179,y:78,width:161,height:175)
        case "observe": b=CGRect(x:174,y:65,width:184,height:176)
        default: b=CGRect(x:202,y:88,width:155,height:157)
        }
        return CGRect(origin:canvas(b.origin),size:CGSize(width:b.width*scale,height:b.height*scale))
    }
    private static let context=CIContext(options:[.cacheIntermediates:false])
    private static let sources=images.mapValues { CIImage(cgImage:$0) }
    private static let kernel=CIWarpKernel(source:"""
    kernel vec2 deskRig(vec4 motion, vec4 detail, vec4 eyes, float scene, float t) {
        vec2 p=destCoord(); float x=p.x,y=500.0-p.y;
        vec2 d=vec2(0.0);
        if (scene < 0.5) {
            float wl=smoothstep(165.0,183.0,x)*(1.0-smoothstep(240.0,257.0,x))*smoothstep(280.0,320.0,y)*(1.0-smoothstep(366.0,382.0,y));
            float wm=smoothstep(302.0,325.0,x)*(1.0-smoothstep(389.0,407.0,x))*smoothstep(282.0,325.0,y)*(1.0-smoothstep(405.0,424.0,y));
            float wr=smoothstep(307.0,326.0,x)*(1.0-smoothstep(375.0,390.0,x))*smoothstep(290.0,321.0,y)*(1.0-smoothstep(366.0,380.0,y));
            d=vec2(motion.x*wl,motion.y*wl);
        }
        return vec2(p.x-d.x,p.y+d.y);
    }
    """)
    private static func bitmapContext()->CGContext {
        CGContext(data:nil,width:512,height:460,bitsPerComponent:8,bytesPerRow:512*4,
                  space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    private static func drawImage(_ image:CGImage,in c:CGContext,rect:CGRect) {
        c.saveGState();c.translateBy(x:rect.minX,y:rect.maxY);c.scaleBy(x:1,y:-1)
        c.draw(image,in:CGRect(origin:.zero,size:rect.size));c.restoreGState()
    }
    private static let workBackground:CIImage? = {
        guard images["sit_base"] != nil else { return nil }
        let folder=ProcessInfo.processInfo.environment["KUROCAT_ARTWORK_DIR"].map { URL(fileURLWithPath:$0) }
            ?? Bundle.main.resourceURL!.appendingPathComponent("CustomCat")
        guard let src=NSImage(contentsOf:folder.appendingPathComponent("desk-work-clean.png")),
              let full=src.cgImage(forProposedRect:nil,context:nil,hints:nil),
              let clean=full.cropping(to:CGRect(x:0,y:40,width:512,height:460)) else { return nil }
        return CIImage(cgImage:clean)
    }()
    private static let mouseLimb:CIImage? = {
        guard let original=images["sit_base"] else { return nil }
        let c=bitmapContext();c.translateBy(x:0,y:460);c.scaleBy(x:1,y:-1)
        c.translateBy(x:0,y:-40)
        let path=CGMutablePath()
        path.move(to:CGPoint(x:330,y:278))
        path.addCurve(to:CGPoint(x:376,y:337),control1:CGPoint(x:361,y:282),control2:CGPoint(x:380,y:310))
        path.addCurve(to:CGPoint(x:371,y:361),control1:CGPoint(x:380,y:348),control2:CGPoint(x:379,y:356))
        path.addCurve(to:CGPoint(x:390,y:389),control1:CGPoint(x:382,y:364),control2:CGPoint(x:389,y:378))
        path.addCurve(to:CGPoint(x:376,y:405),control1:CGPoint(x:393,y:400),control2:CGPoint(x:387,y:405))
        path.addCurve(to:CGPoint(x:332,y:391),control1:CGPoint(x:351,y:407),control2:CGPoint(x:332,y:405))
        path.addCurve(to:CGPoint(x:337,y:363),control1:CGPoint(x:328,y:379),control2:CGPoint(x:330,y:370))
        path.addCurve(to:CGPoint(x:320,y:346),control1:CGPoint(x:325,y:365),control2:CGPoint(x:319,y:358))
        path.addCurve(to:CGPoint(x:330,y:278),control1:CGPoint(x:318,y:321),control2:CGPoint(x:326,y:293))
        path.closeSubpath();c.addPath(path);c.clip()
        drawImage(original,in:c,rect:CGRect(x:0,y:40,width:512,height:460))
        return c.makeImage().map { CIImage(cgImage:$0) }
    }()
    private static let limbKernel=CIWarpKernel(source:"""
        kernel vec2 moveMouseLimb(vec2 offset,float click) {
            vec2 p=destCoord();float y=500.0-p.y;
            float follow=smoothstep(278.0,315.0,y);
            float press=smoothstep(300.0,322.0,y)*(1.0-smoothstep(365.0,380.0,y));
            return vec2(p.x-offset.x*follow,p.y+offset.y*follow+click*press);
        }
        """)
    private static let pupils:[CGImage] = {
        guard let source=images["sit_base"] else { return [] }
        return [CGFloat(249),CGFloat(300)].compactMap { x in
            guard let patch=source.cropping(to:CGRect(x:x,y:125,width:13,height:18)) else { return nil }
            let c=CGContext(data:nil,width:13,height:18,bitsPerComponent:8,bytesPerRow:52,
                            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.addEllipse(in:CGRect(x:0.7,y:0.6,width:11.6,height:16.4));c.clip()
            c.draw(patch,in:CGRect(x:0,y:0,width:13,height:18))
            return c.makeImage()
        }
    }()
    private static func drawTrackedEyes(in c:CGContext,physics p:CatPhysics) {
        guard pupils.count==2 else { return }
        let dx=max(-1,min(1,p.eyeGaze.point.x))*4.4
        let dy=max(-1,min(1,p.eyeGaze.point.y))*2.6
        for (i,x) in [CGFloat(253),CGFloat(308)].enumerated() {
            c.saveGState()
            c.addEllipse(in:CGRect(x:x-11.3,y:124.7,width:22.6,height:20.6));c.clip()
            let colors=[NSColor(calibratedRed:0.80,green:0.78,blue:0.28,alpha:1).cgColor,
                        NSColor(calibratedRed:0.68,green:0.66,blue:0.20,alpha:1).cgColor] as CFArray
            let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1])!
            c.drawRadialGradient(gradient,startCenter:CGPoint(x:x-3,y:132),startRadius:0,
                                 endCenter:CGPoint(x:x,y:135),endRadius:14,options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
            drawImage(pupils[i],in:c,rect:CGRect(x:x+dx-6.5,y:135+dy-9,width:13,height:18))
            c.restoreGState()
        }
    }
    static func animatedImage(_ id:String,physics p:CatPhysics)->CGImage? {
        if id != "sit_base" {
            return DeskCatIdleAnimation.image(id,age:p.customPoseAge,gaze:p.eyeGaze.point) ?? images[id]
        }
        guard let originalSource=sources[id],let kernel else { return images[id] }
        let source = id == "sit_base" ? (workBackground ?? originalSource) : originalSource
        let index=sceneIDs.firstIndex(of:id) ?? 0
        let eyes:CIVector
        switch id {
        case "sit_base": eyes=CIVector(x:253,y:175,z:308,w:175)
        case "wave": eyes=CIVector(x:219,y:157,z:263,w:178)
        case "belly_hug": eyes=CIVector(x:309,y:137,z:358,w:169)
        case "observe": eyes=CIVector(x:305,y:161,z:0,w:0)
        default: eyes=CIVector(x:0,y:0,z:0,w:0)
        }
        let motion=CIVector(x:max(-6.5,min(6.5,p.deskPaw.point.x)),y:max(-5,min(1,p.deskPaw.point.y)),
                            z:max(-14,min(14,p.deskMouse.point.x)),w:max(-7,min(7,p.deskMouse.point.y)))
        let detail=CIVector(x:max(-1,min(1,p.eyeGaze.point.x))*2.3,
                            y:max(-1,min(1,p.eyeGaze.point.y))*1.7,
                            z:min(1,max(p.mousePressLeft.value,p.mousePressRight.value))*1.6,w:0)
        guard let result=kernel.apply(extent:source.extent,roiCallback:{_,r in r.insetBy(dx:-20,dy:-20)},
              image:source,arguments:[motion,detail,eyes,CGFloat(index),p.time]),
              let output=context.createCGImage(result,from:source.extent) else { return images[id] }
        guard id == "sit_base" else { return output }
        let cg=bitmapContext()
        cg.draw(output,in:CGRect(x:0,y:0,width:512,height:460))
        if let limb=mouseLimb,let limbKernel,
           let moved=limbKernel.apply(extent:limb.extent,roiCallback:{_,r in r.insetBy(dx:-24,dy:-16)},
                                      image:limb,arguments:[CIVector(x:motion.z,y:motion.w),detail.z]),
           let arm=context.createCGImage(moved,from:limb.extent) {
            cg.draw(arm,in:CGRect(x:0,y:0,width:512,height:460))
        }
        cg.translateBy(x:0,y:460);cg.scaleBy(x:1,y:-1)
        if p.effectiveEyeClosure<=0.60 {
            drawTrackedEyes(in:cg,physics:p)
            return cg.makeImage()
        }
        // Eyelids remain local overlays; no head or neck transformation.
        for x:CGFloat in [253,308] {
            cg.setFillColor(NSColor(calibratedRed:0.125,green:0.112,blue:0.102,alpha:1).cgColor)
            cg.fillEllipse(in:CGRect(x:x-13,y:123,width:26,height:24))
            cg.setStrokeColor(NSColor(calibratedRed:0.67,green:0.66,blue:0.27,alpha:1).cgColor)
            cg.setLineWidth(1.8);cg.setLineCap(.round)
            cg.move(to:CGPoint(x:x-9,y:134));cg.addQuadCurve(to:CGPoint(x:x+9,y:134),control:CGPoint(x:x,y:140));cg.strokePath()
        }
        return cg.makeImage()
    }
}


/// Approved six-second idle cycles. Moving limbs are isolated image layers;
/// shoulder/wrist pivots never deform facial pixels or neighbouring body parts.
enum DeskCatIdleAnimation {
    static let poseIDs = ["wave", "rest_side", "belly_hug", "groom_leg", "observe"]
    private static let originals = poseIDs.compactMap { DeskCatArtwork.images[$0] }
    private static let waveClean:CGImage? = {
        let folder=ProcessInfo.processInfo.environment["KUROCAT_ARTWORK_DIR"].map { URL(fileURLWithPath:$0) }
            ?? Bundle.main.resourceURL!.appendingPathComponent("CustomCat")
        return NSImage(contentsOf:folder.appendingPathComponent("idle-wave-underlay.png"))?.cgImage(forProposedRect:nil,context:nil,hints:nil)
    }()
    static func image(_ id:String, age:CGFloat, gaze:CGPoint = .zero)->CGImage? {
        guard originals.count==poseIDs.count, waveClean != nil,
              let index=poseIDs.firstIndex(of:id) else { return nil }
        return renderPose(index,Double(max(0,age)).truncatingRemainder(dividingBy:6),gaze)
    }
    private static func canvas(_ w:Int=512,_ h:Int=460)->CGContext {CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!}
    private static func xyCanvas()->CGContext {let c=canvas();c.translateBy(x:0,y:500);c.scaleBy(x:1,y:-1);c.setShouldAntialias(true);return c}
    private static func draw(_ im:CGImage,_ c:CGContext) {c.saveGState();c.translateBy(x:0,y:500);c.scaleBy(x:1,y:-1);c.draw(im,in:CGRect(x:0,y:0,width:512,height:460));c.restoreGState()}
    private static func smooth(_ a:Double,_ b:Double,_ x:Double)->Double {let q=max(0,min(1,(x-a)/(b-a)));return q*q*(3-2*q)}
    private static func pulse(_ t:Double,_ start:Double,_ duration:Double)->Double {let q=(t-start)/duration;return q>0 && q<1 ? pow(sin(q*Double.pi),2):0}
    private static func lick(_ t:Double)->Double {[0.65,1.18,1.71,3.55,4.08,4.61].map{pulse(t,$0,0.38)}.max()!}
    private static func polygon(_ points:[CGPoint])->CGPath {let p=CGMutablePath();p.addLines(between:points);p.closeSubpath();return p}
    private static func rotate(_ c:CGContext,_ pivot:CGPoint,_ angle:Double) {c.translateBy(x:pivot.x,y:pivot.y);c.rotate(by:angle);c.translateBy(x:-pivot.x,y:-pivot.y)}
    private static func moved(_ point:CGPoint,_ pivot:CGPoint,_ a:Double)->CGPoint {let x=point.x-pivot.x,y=point.y-pivot.y;return CGPoint(x:pivot.x+x*cos(a)-y*sin(a),y:pivot.y+x*sin(a)+y*cos(a))}
    // Explicit isolation; never sample facial pixels into a moving limb layer.
    private static let armRegion=polygon([CGPoint(x:105,y:167),CGPoint(x:146,y:166),CGPoint(x:184,y:208),CGPoint(x:193,y:216),CGPoint(x:201,y:225),CGPoint(x:210,y:234),CGPoint(x:234,y:253),CGPoint(x:242,y:284),CGPoint(x:197,y:292),CGPoint(x:173,y:276),CGPoint(x:144,y:230),CGPoint(x:109,y:214)])
    private static let palmHalf=polygon([CGPoint(x:0,y:40),CGPoint(x:323,y:40),CGPoint(x:181,y:182),CGPoint(x:132,y:231),CGPoint(x:0,y:363)])
    private static let armHalf=polygon([CGPoint(x:177,y:180),CGPoint(x:512,y:180),CGPoint(x:512,y:500),CGPoint(x:0,y:500),CGPoint(x:0,y:357),CGPoint(x:130,y:227)])
    private static func isolated(_ image:CGImage,_ paths:[CGPath])->CGImage {let c=xyCanvas();for p in paths {c.addPath(p);c.clip()};draw(image,c);return c.makeImage()!}
    private static let armLayer=isolated(originals[0],[armRegion,armHalf])
    private static let palmLayer=isolated(originals[0],[armRegion,palmHalf])
    private static let waveBase:CGImage={
     let c=xyCanvas();draw(originals[0],c);c.saveGState();c.addPath(armRegion);c.clip();c.setBlendMode(.copy);draw(waveClean!,c);c.restoreGState();return c.makeImage()!
    }()
    // Fold ONLY the upper half of the tall ear. Lower ear and the other ear stay fixed.
    private static let earTip:CGPath={
     let p=CGMutablePath();p.move(to:CGPoint(x:263,y:180));p.addLine(to:CGPoint(x:327,y:180));p.addLine(to:CGPoint(x:327,y:218));p.addCurve(to:CGPoint(x:263,y:218),control1:CGPoint(x:313,y:225),control2:CGPoint(x:277,y:225));p.closeSubpath();return p
    }()
    private static let earLayer=isolated(originals[1],[earTip])
    private static let earBack:CGImage={let c=xyCanvas();draw(earLayer,c);c.setBlendMode(.sourceIn);c.setFillColor(red:0.15,green:0.125,blue:0.11,alpha:1);c.fill(CGRect(x:0,y:40,width:512,height:460));return c.makeImage()!}()
    private static let napBase:CGImage={let c=xyCanvas();draw(originals[1],c);c.addPath(earTip);c.clip();c.clear(CGRect(x:0,y:40,width:512,height:460));return c.makeImage()!}()

    private static func earTwitch(_ t:Double,_ start:Double,_ down:Double=0.06,_ back:Double=0.14)->Double {
     let age=t-start
     if age<0 || age>down+back {return 0}
     return age<down ? smooth(0,down,age) : 1-smooth(0,back,age-down)
    }
    private static func eye(_ c:CGContext,_ close:Double,_ localX:CGFloat) {
     guard close>0 else{return}
     c.saveGState();c.translateBy(x:335.25,y:153.75);c.rotate(by:atan2(25.5,49.5));c.translateBy(x:localX,y:0)
     c.addEllipse(in:CGRect(x:-14.5,y:-13.5,width:29,height:27));c.clip()
     let gap=CGFloat(1-close)*28
     c.setFillColor(red:36/255,green:30/255,blue:27/255,alpha:1)
     c.fill(CGRect(x:-16,y:-15,width:32,height:15-gap/2));c.fill(CGRect(x:-16,y:gap/2,width:32,height:16))
     if close>0.9 {
      c.setAlpha(smooth(0.9,1,close));c.setStrokeColor(red:0.67,green:0.65,blue:0.25,alpha:1);c.setLineWidth(2.2);c.setLineCap(.round)
      c.move(to:CGPoint(x:-10.5,y:-0.7));c.addQuadCurve(to:CGPoint(x:10.5,y:-0.7),control:CGPoint(x:0,y:3.5));c.strokePath()
     }
     c.restoreGState()
    }
    // Exact previously approved observation renderer, used only for that unchanged pose.
    private static let ci=CIContext(options:[.cacheIntermediates:false])
    private static let observeRig=CIWarpKernel(source:"""
    kernel vec2 approvedObserve(float angle,float squeeze,float offset) {
     vec2 p=destCoord();vec2 q=vec2(p.x,500.0-p.y);vec2 base=vec2(264.0,226.0);vec2 r=q-base;
     float w=(1.0-smoothstep(181.0,259.0,q.y))*smoothstep(155.0,185.0,q.x);
     float a=-angle;vec2 v=vec2(cos(a)*r.x-sin(a)*r.y,sin(a)*r.x+cos(a)*r.y)+base;
     v.x=base.x+(v.x-base.x)/(1.0-squeeze)-offset;
     vec2 s=q+(v-q)*w;return vec2(s.x,500.0-s.y);
    }
    """)!
    private static func renderPose(_ scene:Int,_ t:Double,_ gaze:CGPoint)->CGImage {
     let c=xyCanvas()
     if scene==0 {
      draw(waveBase,c);drawTrackedEyes(0,gaze,in:c)
      let phase=t.truncatingRemainder(dividingBy:3),shoulder=CGPoint(x:211,y:266),wrist=CGPoint(x:153,y:210)
      let env=smooth(0.12,0.4,phase)*(1-smooth(1.78,2.1,phase))
      let a=sin((phase-0.4)*Double.pi*2/0.75)*0.125*env,b=sin((phase-0.4)*Double.pi*2/0.75-0.7)*0.17*env
      let paw=moved(moved(CGPoint(x:134,y:196),wrist,b),shoulder,a)
      if env>0.08 {
       c.saveGState();c.setStrokeColor(red:0.45,green:0.39,blue:0.34,alpha:env*(0.27+0.20*abs(cos(phase*Double.pi*2/0.75))));c.setLineWidth(1.8);c.setLineCap(.round)
       for radius:CGFloat in [35,43] {c.addArc(center:paw,radius:radius,startAngle:2.75,endAngle:3.75,clockwise:false);c.strokePath()};c.restoreGState()
      }
      c.saveGState();rotate(c,shoulder,a)
      // Round shoulder / wrist caps hide only the cut edges; no bitmap deformation.
      c.setFillColor(red:1,green:0.96,blue:0.91,alpha:1);c.fillEllipse(in:CGRect(x:199,y:254,width:25,height:25))
      draw(armLayer,c)
      c.setFillColor(red:1,green:0.96,blue:0.91,alpha:1);c.fillEllipse(in:CGRect(x:145,y:202,width:16,height:16))
      rotate(c,wrist,b);draw(palmLayer,c);c.restoreGState()
      return c.makeImage()!
     }
     if scene==1 {
      let amount=earTwitch(t,0.94)+earTwitch(t,3.70)*0.92+earTwitch(t,4.0,0.045,0.10)*0.24
      if amount<0.001 {draw(originals[1],c);return c.makeImage()!}
      draw(napBase,c)
      let theta=amount*2.0,hinge=CGPoint(x:294,y:221),hingeAngle=0.061
      c.saveGState();c.translateBy(x:hinge.x,y:hinge.y);c.rotate(by:hingeAngle);c.scaleBy(x:1,y:cos(theta));c.rotate(by:-hingeAngle);c.translateBy(x:-hinge.x,y:-hinge.y)
      if theta<Double.pi/2 {draw(earLayer,c)} else {
       // The reverse of the folded tip has dark outer fur, not a stretched pink triangle.
       draw(earBack,c)
       // Rounded silhouette and warm rim make the forward-folded outer surface readable.
       let fold=CGMutablePath();fold.move(to:CGPoint(x:268,y:219));fold.addCurve(to:CGPoint(x:296,y:190),control1:CGPoint(x:279,y:190),control2:CGPoint(x:286,y:185));fold.addCurve(to:CGPoint(x:322,y:219),control1:CGPoint(x:310,y:192),control2:CGPoint(x:318,y:207));fold.addQuadCurve(to:CGPoint(x:268,y:219),control:CGPoint(x:295,y:227));fold.closeSubpath()
       c.addPath(fold);c.setFillColor(red:0.20,green:0.168,blue:0.145,alpha:1);c.setStrokeColor(red:0.34,green:0.29,blue:0.25,alpha:0.45);c.setLineWidth(1.1);c.drawPath(using:.fillStroke)
      }
      c.restoreGState()
      if amount>0.1 {
       c.setStrokeColor(red:0.12,green:0.10,blue:0.09,alpha:amount*0.22);c.setLineWidth(1.0);c.setLineCap(.round)
       c.move(to:CGPoint(x:277,y:220));c.addQuadCurve(to:CGPoint(x:312,y:221),control:CGPoint(x:294,y:225));c.strokePath()
      }
      return c.makeImage()!
     }
     if scene==2 {
      let env=smooth(0.7,1.2,t)*(1-smooth(4.6,5.2,t)),wiggle=sin(t*Double.pi*2/1.4)*env
      // Rigid transform preserves every limb's proportions and the head/body connection.
      c.translateBy(x:wiggle*0.5,y:0);rotate(c,CGPoint(x:267,y:391),wiggle*0.008)
      draw(originals[2],c);drawTrackedEyes(2,gaze,in:c)
      let close=smooth(0.35,1.05,t)*(1-smooth(4.8,5.55,t)),spacing:CGFloat=hypot(49.5,25.5)/2
      eye(c,close,-spacing);eye(c,close,spacing)
      return c.makeImage()!
     }
     if scene==3 {
      draw(originals[3],c)
      let e=lick(t)
      if e>0.015 {
       // Nose, philtrum, tongue root and centre crease share one face-local axis.
       // The illustrated face is tilted, so the tongue follows that axis rather than screen vertical.
       let mouth=CGPoint(x:227,y:292),length=CGFloat(18*e)
       c.saveGState();c.translateBy(x:mouth.x,y:mouth.y);c.rotate(by:-atan2(3.5,12.5))
       c.setFillColor(red:0.80,green:0.49,blue:0.50,alpha:1);c.setStrokeColor(red:0.36,green:0.24,blue:0.23,alpha:1);c.setLineWidth(1.2)
       // Both outline halves are exact mirrors about x=0; no lateral drift during extension.
       c.move(to:CGPoint(x:-4.2,y:0));c.addCurve(to:CGPoint(x:-5.1,y:length),control1:CGPoint(x:-4.6,y:min(4,length*0.4)),control2:CGPoint(x:-5.1,y:max(length*0.7,length-3)))
       c.addCurve(to:CGPoint(x:5.1,y:length),control1:CGPoint(x:-5.1,y:length+4),control2:CGPoint(x:5.1,y:length+4))
       c.addCurve(to:CGPoint(x:4.2,y:0),control1:CGPoint(x:5.1,y:max(length*0.7,length-3)),control2:CGPoint(x:4.6,y:min(4,length*0.4)));c.closePath();c.drawPath(using:.fillStroke)
       if e>0.3 {c.setStrokeColor(red:0.64,green:0.36,blue:0.38,alpha:1);c.setLineWidth(0.7);c.move(to:CGPoint(x:0,y:3));c.addLine(to:CGPoint(x:0,y:length-0.5));c.strokePath()}
       c.restoreGState()
       // Restore only the thin upper mouth edge; the old tall mask pushed the visible tongue below the mouth.
       c.saveGState();c.clip(to:CGRect(x:217,y:290.5,width:20,height:1.7));draw(originals[3],c);c.restoreGState()
      }
      return c.makeImage()!
     }
     let im=canvas();im.draw(originals[4],in:CGRect(x:0,y:0,width:512,height:460));im.saveGState();im.translateBy(x:0,y:500);im.scaleBy(x:1,y:-1);drawTrackedEyes(4,gaze,in:im);im.restoreGState();let input=CIImage(cgImage:im.makeImage()!)
     let phase=t*Double.pi*2/6,s=sin(phase)
     let result=observeRig.apply(extent:input.extent,roiCallback:{_,r in r.insetBy(dx:-40,dy:-40)},image:input,arguments:[s*0.038,(1-cos(phase))*0.015,s*2.6])!
     return ci.createCGImage(result,from:input.extent)!
    }

    // Eye outlines and pupil silhouettes come from the source pixels. In particular,
    // the profile eye must not be replaced by a generic circle on the white blaze.
    private struct TrackedEye {
        let bounds:CGRect
        let outline:CGPath
        let iris:CGImage
        let pupil:CGImage
    }
    private struct EyePixel {
        let point:CGPoint
        let r:CGFloat
        let g:CGFloat
        let b:CGFloat
    }
    private static func cross(_ o:CGPoint,_ a:CGPoint,_ b:CGPoint)->CGFloat {
        (a.x-o.x)*(b.y-o.y)-(a.y-o.y)*(b.x-o.x)
    }
    private static func hull(_ points:[CGPoint])->[CGPoint] {
        let sorted=points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        var lower:[CGPoint]=[],upper:[CGPoint]=[]
        for p in sorted {
            while lower.count>=2 && cross(lower[lower.count-2],lower[lower.count-1],p)<=0 {lower.removeLast()}
            lower.append(p)
        }
        for p in sorted.reversed() {
            while upper.count>=2 && cross(upper[upper.count-2],upper[upper.count-1],p)<=0 {upper.removeLast()}
            upper.append(p)
        }
        return Array(lower.dropLast())+Array(upper.dropLast())
    }
    private static func makeEye(_ scene:Int,_ search:CGRect)->TrackedEye? {
        let original=NSBitmapImageRep(cgImage:originals[scene])
        var yellow:[EyePixel]=[]
        for y in Int(search.minY)..<Int(search.maxY) {
            for x in Int(search.minX)..<Int(search.maxX) {
                guard let c=original.colorAt(x:x,y:y-40)?.usingColorSpace(.deviceRGB) else {continue}
                if c.redComponent>0.39 && c.greenComponent>0.39 && c.blueComponent<0.44 &&
                    min(c.redComponent,c.greenComponent)-c.blueComponent>0.14 {
                    yellow.append(EyePixel(point:CGPoint(x:CGFloat(x)+0.5,y:CGFloat(y)+0.5),r:c.redComponent,g:c.greenComponent,b:c.blueComponent))
                }
            }
        }
        guard yellow.count>15 else {return nil}
        let contour=hull(yellow.map(\.point)),outline=polygon(contour)
        let bounds=outline.boundingBoxOfPath.insetBy(dx:-1,dy:-1).integral
        let width=Int(bounds.width),height=Int(bounds.height)
        // Restrict extraction to the dark pupil and its antialiased edge;
        // darker variations elsewhere in the golden iris are texture, not pupil pixels.
        var pupilArea=Set<Int>()
        for y in 0..<height {for x in 0..<width {
            let point=CGPoint(x:bounds.minX+CGFloat(x)+0.5,y:bounds.minY+CGFloat(y)+0.5)
            guard outline.contains(point),
                  let c=original.colorAt(x:Int(bounds.minX)+x,y:Int(bounds.minY)+y-40)?.usingColorSpace(.deviceRGB),
                  max(c.redComponent,max(c.greenComponent,c.blueComponent))<0.45,
                  abs(c.greenComponent-c.blueComponent)<0.13 else {continue}
            for dy in -2...2 {for dx in -2...2 where dx*dx+dy*dy<=4 {
                let xx=x+dx,yy=y+dy
                if xx>=0 && yy>=0 && xx<width && yy<height {pupilArea.insert(yy*width+xx)}
            }}
        }}
        var irisBytes=[UInt8](repeating:0,count:width*height*4)
        var pupilBytes=irisBytes
        func write(_ bytes:inout [UInt8],_ x:Int,_ y:Int,_ r:CGFloat,_ g:CGFloat,_ b:CGFloat,_ a:CGFloat) {
            let i=(y*width+x)*4
            for (offset,value) in [r,g,b,a].enumerated() {bytes[i+offset]=UInt8(max(0,min(255,(value*255).rounded())))}
        }
        for y in 0..<height {for x in 0..<width {
            let point=CGPoint(x:bounds.minX+CGFloat(x)+0.5,y:bounds.minY+CGFloat(y)+0.5)
            guard let c=original.colorAt(x:Int(bounds.minX)+x,y:Int(bounds.minY)+y-40)?.usingColorSpace(.deviceRGB) else {continue}
            write(&irisBytes,x,y,c.redComponent,c.greenComponent,c.blueComponent,c.alphaComponent)
            guard outline.contains(point),pupilArea.contains(y*width+x) else {continue}
            let highlight=c.redComponent>0.65 && c.greenComponent>0.65 && c.blueComponent>0.55
            guard c.greenComponent<0.68 || highlight else {continue}
            // Reconstruct only the pupil hole from nearby original iris colours;
            // the original golden border and its irregular silhouette remain intact.
            let neighbours=yellow.sorted {
                hypot($0.point.x-point.x,$0.point.y-point.y)<hypot($1.point.x-point.x,$1.point.y-point.y)
            }.prefix(12)
            var total:CGFloat=0,r:CGFloat=0,g:CGFloat=0,b:CGFloat=0
            for n in neighbours {
                let dx=n.point.x-point.x,dy=n.point.y-point.y,w=1/max(1,dx*dx+dy*dy)
                total+=w;r+=n.r*w;g+=n.g*w;b+=n.b*w
            }
            r/=total;g/=total;b/=total
            let alpha:CGFloat=highlight ? 1 : max(0,min(1,max((r-c.redComponent)/max(r,0.01),max((g-c.greenComponent)/max(g,0.01),(b-c.blueComponent)/max(b,0.01)))))
            guard alpha>0.035 else {continue}
            write(&irisBytes,x,y,r,g,b,1)
            func unmatte(_ value:CGFloat,_ background:CGFloat)->CGFloat {max(0,min(1,(value-background*(1-alpha))/alpha))}
            write(&pupilBytes,x,y,unmatte(c.redComponent,r),unmatte(c.greenComponent,g),unmatte(c.blueComponent,b),alpha)
        }}
        func image(_ bytes:[UInt8])->CGImage? {
            guard let provider=CGDataProvider(data:Data(bytes) as CFData) else {return nil}
            return CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),
                provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)
        }
        guard let irisImage=image(irisBytes),let pupilImage=image(pupilBytes) else {return nil}
        return TrackedEye(bounds:bounds,outline:outline,iris:irisImage,pupil:pupilImage)
    }
    private static let trackingEyes:[Int:[TrackedEye]] = {
        let searches:[Int:[CGRect]] = [
            0:[CGRect(x:201,y:144,width:34,height:31),CGRect(x:247,y:161,width:33,height:34)],
            2:[CGRect(x:294,y:122,width:35,height:38),CGRect(x:343,y:149,width:35,height:36)],
            4:[CGRect(x:283,y:133,width:35,height:39)]
        ]
        var result:[Int:[TrackedEye]]=[:]
        for (scene,rects) in searches {result[scene]=rects.compactMap {makeEye(scene,$0)}}
        return result
    }()
    private static func drawPatch(_ image:CGImage,_ bounds:CGRect,in c:CGContext) {
        c.saveGState();c.translateBy(x:bounds.minX,y:bounds.maxY);c.scaleBy(x:1,y:-1)
        c.draw(image,in:CGRect(origin:.zero,size:bounds.size));c.restoreGState()
    }
    private static func drawTrackedEyes(_ scene:Int,_ gaze:CGPoint,in c:CGContext) {
        guard abs(gaze.x)+abs(gaze.y)>0.02,let eyes=trackingEyes[scene] else {return}
        let dx=max(-1,min(1,gaze.x))*2.4,dy=max(-1,min(1,gaze.y))*1.4
        for eye in eyes {
            c.saveGState();c.addPath(eye.outline);c.clip()
            drawPatch(eye.iris,eye.bounds,in:c)
            drawPatch(eye.pupil,eye.bounds.offsetBy(dx:dx,dy:dy),in:c)
            c.restoreGState()
        }
    }
}
