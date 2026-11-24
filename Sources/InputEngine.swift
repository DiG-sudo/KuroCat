import Foundation
import AppKit
import IOKit
import IOKit.hid
import ApplicationServices

enum InputEngineStatus: String {
    case fullHardware = "硬件级全状态监听中 (HID + EventTap)"
    case hidOnly = "硬件 HID 监听中 (游戏/打字全支持)"
    case eventTapOnly = "全局事件监听中 (EventTap)"
    case needsPermission = "需开启「输入监控」以全局监听键盘"
}

/// Dual-layer full-state keyboard & mouse capture engine for macOS.
/// Layer 1: IOHIDManager (kernel HID — true NKRO, works in games, IME, modifiers, long holds).
/// Layer 2: CGEventTap (.listenOnly — catches trackpad taps, virtual/remapped keys, scroll).
/// Layer 3: Local NSEvent + mouseLocation (always active even before permissions).
final class InputEngine {
    static let shared = InputEngine()

    // Unified active state
    private var hidPressedKeys = Set<PhysicalKey>()
    private var tapPressedKeys = Set<PhysicalKey>()
    private(set) var activeKeys = Set<PhysicalKey>()
    private(set) var pressedOrder: [PhysicalKey] = []

    // Mouse state
    private(set) var leftMouseDown = false
    private(set) var rightMouseDown = false
    private(set) var otherMouseDown = false
    private(set) var lastMouseMoveTime: CFTimeInterval = 0
    private(set) var lastMouseClickTime: CFTimeInterval = 0
    private(set) var lastKeyActivityTime: CFTimeInterval = 0
    private(set) var lastMouseLocation: CGPoint = NSEvent.mouseLocation
    private(set) var mouseVelocity: CGVector = .zero

    // Stats
    private(set) var totalKeystrokesToday: Int = 0
    private var recentKeyTimes: [CFTimeInterval] = []
    private var statsDayString: String = ""

    // Engine handles
    private var hidManager: IOHIDManager?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var lastRepeatStamps: [PhysicalKey:UInt64] = [:]
    private(set) var receivedKeyDownCount = 0
    private(set) var receivedModifierCount = 0
    private(set) var deliveredKeyDownCount = 0
    private(set) var syntheticTestCodes = Set<UInt16>()
    private var modifierStamps: [PhysicalKey:UInt64] = [:]
    private var permissionCheckTimer: Timer?

    private(set) var isHIDActive = false
    private(set) var isTapActive = false

    // Callbacks
    var onKeyDown: ((PhysicalKey) -> Void)?
    var onKeyUp: ((PhysicalKey) -> Void)?
    var onMouseClick: ((Int, Bool) -> Void)?   // button (0=L,1=R,2=Other), isDown
    var onStatusChanged: ((InputEngineStatus) -> Void)?

    private var lastModifierFlags: CGEventFlags = []
    private var recentDownTimes: [PhysicalKey:CFTimeInterval] = [:]

    var status: InputEngineStatus {
        guard hasKeyboardGlobalPermission else { return .needsPermission }
        if isHIDActive && isTapActive { return .fullHardware }
        if isHIDActive { return .hidOnly }
        if isTapActive { return .eventTapOnly }
        return .needsPermission
    }

    var hasInputMonitoringPermission: Bool {
        CGPreflightListenEventAccess() || (IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted)
    }

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    var hasKeyboardGlobalPermission: Bool {
        hasInputMonitoringPermission || hasAccessibilityPermission
    }

    var currentKPM: Int {
        let now = CACurrentMediaTime()
        let cutoff = now - 10.0
        let count = recentKeyTimes.filter { $0 >= cutoff }.count
        return count * 6
    }

    private init() {
        loadStats()
    }

    func start() {
        startLocalFallbackMonitor()
        startGlobalFallbackMonitor()
        tryStartHID()
        tryStartEventTap()
        notifyStatus()

        // Periodically check if the user just granted Input Monitoring permission
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let prevStatus = self.status
            if !self.isHIDActive && self.hasInputMonitoringPermission {
                self.tryStartHID()
            }
            if !self.isTapActive && (self.hasInputMonitoringPermission || self.hasAccessibilityPermission) {
                self.tryStartEventTap()
            }
            if self.status != prevStatus {
                self.notifyStatus()
            }
        }
    }

    func stop() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
        stopHID()
        stopEventTap()
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor=nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor=nil }
    }

    /// Request macOS Input Monitoring permission and open System Settings directly.
    func requestPermissionsAndOpenSettings() {
        CGRequestListenEventAccess()
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Called at 60fps from the render loop to sample global cursor motion (requires zero permissions).
    func pollMouse(dt: CGFloat) {
        let loc = NSEvent.mouseLocation
        let dx = loc.x - lastMouseLocation.x
        let dy = loc.y - lastMouseLocation.y
        let dist = hypot(dx, dy)
        if dist > 0.4 {
            lastMouseMoveTime = CACurrentMediaTime()
            if dt > 0.001 {
                mouseVelocity = CGVector(dx: dx / dt, dy: dy / dt)
            }
        } else {
            mouseVelocity = CGVector(dx: mouseVelocity.dx * 0.82, dy: mouseVelocity.dy * 0.82)
        }
        lastMouseLocation = loc

        // Keep KPM sliding window clean
        let now = CACurrentMediaTime()
        if recentKeyTimes.count > 120 {
            recentKeyTimes.removeAll { now - $0 > 12.0 }
        }
    }

    // MARK: - Layer 1: IOHIDManager (Raw Kernel HID — Best for Games + IME)

    private func tryStartHID() {
        guard !isHIDActive else { return }
        guard hasInputMonitoringPermission else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matches: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
            ],
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keypad
            ],
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse
            ]
        ]

        let consumerMatch: [String:Any] = [kIOHIDDeviceUsagePageKey as String:0x0C,kIOHIDDeviceUsageKey as String:1]
        IOHIDManagerSetDeviceMatchingMultiple(manager, (matches+[consumerMatch]) as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            guard let ctx else { return }
            let engine = Unmanaged<InputEngine>.fromOpaque(ctx).takeUnretainedValue()
            engine.handleHIDValue(value)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult == kIOReturnSuccess {
            self.hidManager = manager
            self.isHIDActive = true
        } else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            self.isHIDActive = false
        }
    }

    private func stopHID() {
        if let manager = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }
        isHIDActive = false
        hidPressedKeys.removeAll()
        recomputeUnifiedKeys()
    }

    private func handleHIDValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intVal = IOHIDValueGetIntegerValue(value)

        // Standard Keyboard / Keypad page (0x07)
        if usagePage == UInt32(kHIDPage_KeyboardOrKeypad) {
            // Array slots (usage 0xFFFFFFFF) are report bookkeeping, not a
            // physical key. IOHIDManager reports their derived key elements too.
            if let key = PhysicalKey.fromHIDUsage(usage) {
                setKeyState(key, isDown: intVal != 0, fromHID: true)
            }
            return
        }

        if usagePage == 0x0C && usage > 0 && usage <= 0xFFFF {
            setKeyState(PhysicalKey.fromConsumerUsage(usage),isDown:intVal != 0,fromHID:true)
            return
        }

        // Apple Built-in / Magic Keyboard Fn key (Apple Vendor Top Case page 0xFF, usage 0x03)
        if usagePage == 0xFF && usage == 0x03 {
            setKeyState(.fn, isDown: intVal != 0, fromHID: true)
            return
        }

        // Mouse buttons (Page 0x09)
        if usagePage == UInt32(kHIDPage_Button) {
            let isDown = intVal != 0
            if usage == 1 {
                updateMouseButton(0, isDown: isDown)
            } else if usage == 2 {
                updateMouseButton(1, isDown: isDown)
            } else if usage >= 3 && usage <= 8 {
                updateMouseButton(2, isDown: isDown)
            }
        }
    }

    // MARK: - Layer 2: CGEventTap (Listen-Only Companion for Trackpad, Virtual Keys & Scroll)

    private func tryStartEventTap() {
        guard !isTapActive else { return }
        // Only activate keyboard EventTap when macOS actually granted Input Monitoring or Accessibility;
        // otherwise listenOnly tap silently drops keyboard events while returning non-nil!
        guard hasKeyboardGlobalPermission else { return }

        var mask: CGEventMask = 0
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .scrollWheel, CGEventType(rawValue:14)!
        ]
        for t in types {
            mask |= (1 << t.rawValue)
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, ctx in
                guard let ctx else { return Unmanaged.passUnretained(event) }
                let engine = Unmanaged<InputEngine>.fromOpaque(ctx).takeUnretainedValue()
                engine.handleCGEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        ) else {
            isTapActive = false
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.eventTapRunLoopSource = source
        self.isTapActive = true
    }

    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        eventTapRunLoopSource = nil
        isTapActive = false
        tapPressedKeys.removeAll()
        recomputeUnifiedKeys()
    }

    func handleCGEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        if type.rawValue == 14, let e = NSEvent(cgEvent:event), e.subtype.rawValue == 8,
           let key = PhysicalKey.fromSystemKey((e.data1 >> 16) & 0xFFFF) {
            let down = ((e.data1 >> 8) & 0xFF) == 0xA
            if down && (e.data1 & 1) != 0 { recordRepeat(key,timestamp:event.timestamp) }
            else { setKeyState(key,isDown:down,fromHID:false) }
            return
        }
        switch type {
        case .keyDown:
            receivedKeyDownCount += 1
            // Repeat input animates/bubbles without adding another held-key state.
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if event.getIntegerValueField(.eventSourceUserData)==0x4B55524F { syntheticTestCodes.insert(keyCode) }
            if let key = PhysicalKey.fromCGKeyCode(keyCode) {
                if isRepeat { recordRepeat(key,timestamp:event.timestamp) }
                else { setKeyState(key,isDown:true,fromHID:false) }
            }
        case .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if let key = PhysicalKey.fromCGKeyCode(keyCode) {
                setKeyState(key, isDown: false, fromHID: false)
            }
        case .flagsChanged:
            receivedModifierCount += 1
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            if let key = PhysicalKey.fromCGKeyCode(keyCode) {
                if modifierStamps[key] != event.timestamp {
                    modifierStamps[key]=event.timestamp
                    handleModifier(key,flags:flags)
                }
            }
            lastModifierFlags = flags
        case .leftMouseDown:
            updateMouseButton(0, isDown: true)
        case .leftMouseUp:
            updateMouseButton(0, isDown: false)
        case .rightMouseDown:
            updateMouseButton(1, isDown: true)
        case .rightMouseUp:
            updateMouseButton(1, isDown: false)
        case .otherMouseDown:
            updateMouseButton(2, isDown: true)
        case .otherMouseUp:
            updateMouseButton(2, isDown: false)
        case .scrollWheel:
            lastMouseMoveTime = CACurrentMediaTime()
        default:
            break
        }
    }

    private func handleModifier(_ key:PhysicalKey,flags:CGEventFlags) {
        if key == .capsLock {
            // Caps Lock changes a latch; both on and off transitions are physical presses.
            if !activeKeys.contains(key) && CACurrentMediaTime()-(recentDownTimes[key] ?? 0)>0.08 {
                setKeyState(key,isDown:true,fromHID:false)
                setKeyState(key,isDown:false,fromHID:false)
            }
            return
        }
        setKeyState(key,isDown:isModifierKeyDown(key:key,flags:flags),fromHID:false)
    }

    func isModifierKeyDown(key:PhysicalKey,flags:CGEventFlags)->Bool {
        let device:[PhysicalKey:UInt64] = [.leftControl:1,.leftShift:2,.rightShift:4,.leftCommand:8,.rightCommand:16,.leftOption:32,.rightOption:64,.rightControl:8192]
        if let bit=device[key],flags.rawValue & 0x207F != 0 { return flags.rawValue & bit != 0 }
        let mask:CGEventFlags
        switch key {
        case .leftShift,.rightShift: mask = .maskShift
        case .leftControl,.rightControl: mask = .maskControl
        case .leftOption,.rightOption: mask = .maskAlternate
        case .leftCommand,.rightCommand: mask = .maskCommand
        case .fn: return flags.contains(.maskSecondaryFn)
        default: return false
        }
        // Some synthetic events omit per-device bits; a flags change toggles that side.
        return flags.contains(mask) && !tapPressedKeys.contains(key)
    }

    private func recordRepeat(_ key:PhysicalKey,timestamp:UInt64) {
        // EventTap and AppKit may report the same OS repeat. Count that event once.
        if let last=lastRepeatStamps[key],timestamp>=last,timestamp-last<2_000_000 { return }
        lastRepeatStamps[key]=timestamp
        lastKeyActivityTime=CACurrentMediaTime()
        deliveredKeyDownCount += 1
        onKeyDown?(key)
    }

    private func startGlobalFallbackMonitor() {
        if let old=globalMonitor { NSEvent.removeMonitor(old) }
        globalMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.keyDown,.keyUp,.flagsChanged,.systemDefined]) { [weak self] event in
            guard let self,let cg=event.cgEvent else { return }
            self.handleCGEvent(type:cg.type,event:cg)
        }
    }

    var diagnosticSnapshot:[String:Any] {
        ["inputMonitoring":hasInputMonitoringPermission,"accessibility":hasAccessibilityPermission,
         "hidActive":isHIDActive,"eventTapActive":isTapActive,
         "tapEnabled":eventTap.map { CGEvent.tapIsEnabled(tap:$0) } ?? false,
         "globalMonitorInstalled":globalMonitor != nil,"keyEvents":receivedKeyDownCount,
         "modifierEvents":receivedModifierCount,"deliveredPresses":deliveredKeyDownCount,
         "heldKeyCount":activeKeys.count,"syntheticTestCodes":syntheticTestCodes.sorted(),"status":status.rawValue]
    }

    // MARK: - Layer 3: Local Window Monitor (Immediate testing before permissions)

    private func startLocalFallbackMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .systemDefined]) { [weak self] event in
            guard let self else { return event }
            if let cg=event.cgEvent { self.handleCGEvent(type:cg.type,event:cg) }
            return event
        }
    }

    // MARK: - Unified Deduplicated State

    func setKeyState(_ key: PhysicalKey, isDown: Bool, fromHID: Bool) {
        let wasActive = activeKeys.contains(key)

        if isDown {
            if fromHID { hidPressedKeys.insert(key) }
            else { tapPressedKeys.insert(key) }
        } else {
            // Either backend's key-up is authoritative. A missing HID release must not
            // poison subsequent presses when EventTap already observed the release.
            hidPressedKeys.remove(key)
            tapPressedKeys.remove(key)
            lastRepeatStamps.removeValue(forKey:key)
        }

        recomputeUnifiedKeys()
        let isNowActive = activeKeys.contains(key)

        if !wasActive && isNowActive {
            let now = CACurrentMediaTime()
            lastKeyActivityTime = now
            recentDownTimes[key] = now
            recentKeyTimes.append(now)
            incrementTodayStats()
            pressedOrder.removeAll { $0 == key }
            pressedOrder.append(key)
            deliveredKeyDownCount += 1
            onKeyDown?(key)
        } else if wasActive && !isNowActive {
            pressedOrder.removeAll { $0 == key }
            onKeyUp?(key)
        }
    }

    private func recomputeUnifiedKeys() {
        activeKeys = hidPressedKeys.union(tapPressedKeys)
    }

    private func updateMouseButton(_ button: Int, isDown: Bool) {
        let prev: Bool
        switch button {
        case 0:
            prev = leftMouseDown
            leftMouseDown = isDown
        case 1:
            prev = rightMouseDown
            rightMouseDown = isDown
        default:
            prev = otherMouseDown
            otherMouseDown = isDown
        }
        if prev != isDown {
            let now = CACurrentMediaTime()
            lastMouseMoveTime = now
            if isDown { lastMouseClickTime = now }
            onMouseClick?(button, isDown)
        }
    }

    private func notifyStatus() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onStatusChanged?(self.status)
        }
    }

    // MARK: - Daily Stats Persistence

    private func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func loadStats() {
        let today = todayString()
        statsDayString = today
        let savedDay = UserDefaults.standard.string(forKey: "KuroCat.StatsDay") ?? ""
        if savedDay == today {
            totalKeystrokesToday = UserDefaults.standard.integer(forKey: "KuroCat.TodayKeys")
        } else {
            totalKeystrokesToday = 0
            UserDefaults.standard.set(today, forKey: "KuroCat.StatsDay")
            UserDefaults.standard.set(0, forKey: "KuroCat.TodayKeys")
        }
    }

    private func incrementTodayStats() {
        let today = todayString()
        if today != statsDayString {
            statsDayString = today
            totalKeystrokesToday = 0
            UserDefaults.standard.set(today, forKey: "KuroCat.StatsDay")
        }
        totalKeystrokesToday += 1
        if totalKeystrokesToday % 10 == 0 {
            UserDefaults.standard.set(totalKeystrokesToday, forKey: "KuroCat.TodayKeys")
        }
    }

    func flushStats() {
        UserDefaults.standard.set(statsDayString, forKey: "KuroCat.StatsDay")
        UserDefaults.standard.set(totalKeystrokesToday, forKey: "KuroCat.TodayKeys")
    }
}
