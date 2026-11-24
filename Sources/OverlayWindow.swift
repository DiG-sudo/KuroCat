import Foundation
import AppKit

final class CatCanvasView: NSView {
    let physics = CatPhysics()
    var onRequestPermission: (() -> Void)?
    var onRightClickMenu: ((NSEvent) -> NSMenu?)?

    private var lastHoverCanvasPt: CGPoint?
    private var isDragging = false
    private var dragStartScreenPt: CGPoint = .zero
    private var dragStartWindowOrigin: CGPoint = .zero
    private var isShowingOpenHand = false
    private(set) var isPresentingMenu = false

    // The nested menu loop owns the pointer until the menu closes.
    func setMenuTracking(_ tracking: Bool) {
        isPresentingMenu = tracking
        lastHoverCanvasPt = nil
        if tracking {
            isDragging = false
            resetCursorIfNeeded()
            NSCursor.arrow.set()
            window?.ignoresMouseEvents = false
        } else {
            updateHoverAndClickThrough()
        }
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        let scaleX = bounds.width / CatPhysics.canvasSize.width
        let scaleY = bounds.height / CatPhysics.canvasSize.height
        ctx.saveGState()
        ctx.scaleBy(x: scaleX, y: scaleY)

        let showPill = InputEngine.shared.status == .needsPermission
        CatRenderer.draw(in: ctx, physics: physics, showPermissionPill: showPill)

        ctx.restoreGState()
    }

    func canvasPoint(fromScreenPoint screenPt: CGPoint) -> CGPoint? {
        guard let win = window else { return nil }
        let frame = win.frame
        guard frame.contains(screenPt) else { return nil }
        let localX = (screenPt.x - frame.minX) / frame.width * CatPhysics.canvasSize.width
        // Convert bottom-up screen Y to flipped top-down canvas Y
        let localY = (frame.maxY - screenPt.y) / frame.height * CatPhysics.canvasSize.height
        return CGPoint(x: localX, y: localY)
    }

    /// Called on every 60fps tick to handle smart click-through AND petting strokes.
    func updateHoverAndClickThrough() {
        guard !isPresentingMenu, let win = window else { return }
        let screenPt = NSEvent.mouseLocation
        let showPill = InputEngine.shared.status == .needsPermission

        if isDragging {
            win.ignoresMouseEvents = false
            return
        }

        guard let pt = canvasPoint(fromScreenPoint: screenPt) else {
            lastHoverCanvasPt = nil
            if !win.ignoresMouseEvents {
                win.ignoresMouseEvents = true
            }
            resetCursorIfNeeded()
            return
        }

        let zone = CatRenderer.hitTest(point: pt, physics: physics, showPermissionPill: showPill)

        // Petting works in both Smart Mode and Full Click-Through Mode!
        if (zone == .head || zone == .body) && !physics.isManualCustomAction {
            if let prev = lastHoverCanvasPt {
                let delta = hypot(pt.x - prev.x, pt.y - prev.y)
                if delta > 1.2 && delta < 80 {
                    physics.registerPetStroke(canvasPoint: pt, delta: delta, isHead: zone == .head)
                }
            }
            lastHoverCanvasPt = pt
        } else {
            lastHoverCanvasPt = nil
        }

        // Smart Click-Through logic (hold Option ⌥ to temporarily unlock Full Click-Through!)
        let optionHeld = NSEvent.modifierFlags.contains(.option)
        if CatSettings.shared.fullClickThrough && !optionHeld {
            // Keep permission pill clickable only if permission isn't granted yet
            win.ignoresMouseEvents = (zone != .permissionPill)
            resetCursorIfNeeded()
        } else {
            let shouldCapture = (zone != .none)
            if win.ignoresMouseEvents == shouldCapture {
                win.ignoresMouseEvents = !shouldCapture
            }
            if zone == .head || zone == .body {
                if !isShowingOpenHand {
                    NSCursor.openHand.set()
                    isShowingOpenHand = true
                }
            } else if zone == .permissionPill {
                NSCursor.pointingHand.set()
                isShowingOpenHand = false
            } else {
                resetCursorIfNeeded()
            }
        }
    }

    private func resetCursorIfNeeded() {
        if isShowingOpenHand {
            NSCursor.arrow.set()
            isShowingOpenHand = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with:event)
            return
        }
        guard !isPresentingMenu, let win = window else { return }
        let screenPt = NSEvent.mouseLocation
        let showPill = InputEngine.shared.status == .needsPermission

        if let pt = canvasPoint(fromScreenPoint: screenPt) {
            let zone = CatRenderer.hitTest(point: pt, physics: physics, showPermissionPill: showPill)
            if zone == .permissionPill {
                onRequestPermission?()
                return
            }
        }

        isDragging = true
        dragStartScreenPt = screenPt
        dragStartWindowOrigin = win.frame.origin
        isShowingOpenHand = false
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let win = window else { return }
        let currentScreenPt = NSEvent.mouseLocation
        let newOrigin = CGPoint(
            x: dragStartWindowOrigin.x + (currentScreenPt.x - dragStartScreenPt.x),
            y: dragStartWindowOrigin.y + (currentScreenPt.y - dragStartScreenPt.y)
        )
        win.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging, let win = window else { return }
        isDragging = false
        NSCursor.arrow.set()
        (win as? OverlayWindow)?.keepOnScreen()
        updateHoverAndClickThrough()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onRightClickMenu?(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !isPresentingMenu else { return }
        // AppKit owns context-menu positioning, activation and multi-screen input.
        super.rightMouseDown(with:event)
    }
}

final class OverlayWindow: NSPanel {
    let catView = CatCanvasView()

    init() {
        let scale = CatSettings.shared.scale
        let size = CGSize(
            width: CatPhysics.canvasSize.width * scale,
            height: CatPhysics.canvasSize.height * scale
        )
        let origin = OverlayWindow.initialOrigin(for: size)

        super.init(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true

        applyWindowLevelAndBehavior()

        catView.frame = CGRect(origin: .zero, size: size)
        catView.autoresizingMask = [.width, .height]
        contentView = catView
    }

    func applyWindowLevelAndBehavior() {
        if CatSettings.shared.fullScreenOverlay {
            level = .statusBar
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        } else {
            level = .floating
            collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        }
    }

    func applyScale(_ requestedScale: CGFloat) {
        let newScale = requestedScale.isFinite ? min(1.5, max(0.65, requestedScale)) : 1.0
        CatSettings.shared.scale = newScale
        let oldFrame = frame
        let newSize = CGSize(
            width: CatPhysics.canvasSize.width * newScale,
            height: CatPhysics.canvasSize.height * newScale
        )
        // Anchor bottom-center so scaling feels grounded
        let newOrigin = CGPoint(
            x: oldFrame.midX - newSize.width * 0.5,
            y: oldFrame.minY
        )
        setFrame(Self.fittedFrame(CGRect(origin: newOrigin, size: newSize),
                                 visibleFrames: NSScreen.screens.map(\.visibleFrame)), display: true)
        savePosition()
        catView.updateHoverAndClickThrough()
    }

    func resetPosition() {
        let origin = OverlayWindow.defaultOrigin(for: frame.size)
        setFrameOrigin(origin)
        keepOnScreen()
    }

    func keepOnScreen() {
        setFrame(Self.fittedFrame(frame, visibleFrames: NSScreen.screens.map(\.visibleFrame)), display: true)
        savePosition()
    }

    private func savePosition() {
        UserDefaults.standard.set(Double(frame.minX), forKey: "KuroCat.PosX")
        UserDefaults.standard.set(Double(frame.minY), forKey: "KuroCat.PosY")
    }

    // Prefer the display containing most of the pet, including negative origins.
    static func fittedFrame(_ frame: CGRect, visibleFrames: [CGRect]) -> CGRect {
        guard !visibleFrames.isEmpty else { return frame }
        let screen = visibleFrames.max { a, b in
            func score(_ r: CGRect) -> CGFloat {
                let overlap = r.intersection(frame)
                if !overlap.isNull { return overlap.width * overlap.height }
                return -hypot(r.midX-frame.midX, r.midY-frame.midY)
            }
            return score(a) < score(b)
        }!
        var result = frame
        result.origin.x = min(max(frame.minX, screen.minX), max(screen.minX, screen.maxX-frame.width))
        result.origin.y = min(max(frame.minY, screen.minY), max(screen.minY, screen.maxY-frame.height))
        return result
    }

    private static func initialOrigin(for size: CGSize) -> CGPoint {
        let d = UserDefaults.standard
        if d.object(forKey: "KuroCat.PosX") != nil && d.object(forKey: "KuroCat.PosY") != nil {
            let x = CGFloat(d.double(forKey: "KuroCat.PosX"))
            let y = CGFloat(d.double(forKey: "KuroCat.PosY"))
            if x.isFinite && y.isFinite {
                return fittedFrame(CGRect(origin: CGPoint(x:x,y:y), size:size),
                                   visibleFrames: NSScreen.screens.map(\.visibleFrame)).origin
            }
        }
        return defaultOrigin(for: size)
    }

    private static func defaultOrigin(for size: CGSize) -> CGPoint {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(
            x: screen.maxX - size.width - 28,
            y: screen.minY + 18
        )
    }
}
