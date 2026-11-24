import Foundation
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private(set) var statusItem: NSStatusItem!
    private var overlayWindow: OverlayWindow!
    private var renderTimer: Timer?
    private var lastFrameTime: CFTimeInterval = CACurrentMediaTime()
    private var isPetVisible = true
    private var lastDiagnosticTime:CFTimeInterval = 0
    private var trackingMenus = Set<ObjectIdentifier>()
    private var screenObserver: NSObjectProtocol?
    var isMenuTracking: Bool { !trackingMenus.isEmpty }
    private(set) lazy var contextMenu: NSMenu = buildMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        CatSettings.shared.coatTheme = .customTuxedo
        CatSettings.shared.eyeTheme = .photoOlive
        NSApp.setActivationPolicy(.accessory)

        setupOverlay()

        // Wire dual-layer InputEngine -> CatPhysics
        let engine = InputEngine.shared
        // HID, EventTap and AppKit monitors all deliver on the main run loop.
        // Apply immediately so a queued menu click cannot cancel a newly chosen pose.
        engine.onKeyDown = { [weak self] key in
            guard let self, self.isPetVisible, !self.isMenuTracking else { return }
            self.overlayWindow.catView.physics.triggerKeyDown(key)
        }
        engine.onMouseClick = { [weak self] button, isDown in
            guard let self, self.isPetVisible, !self.isMenuTracking else { return }
            self.overlayWindow.catView.physics.triggerMouseClick(button: button, isDown: isDown)
        }
        engine.onStatusChanged = { [weak self] _ in self?.writeRuntimeDiagnostics(force:true) }
        engine.start()
        writeRuntimeDiagnostics(force:true)

        setupStatusItem()
        if isAutoStartEnabled() {
            // Keep LaunchAgent path updated if user moved KuroCat.app into /Applications
            _ = setAutoStartEnabled(true)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.overlayWindow.keepOnScreen() }
        startRenderLoop()
    }

    // Keep window/menu setup independent from global input capture.
    func setupOverlay() {
        overlayWindow = OverlayWindow()
        overlayWindow.orderFrontRegardless()

        let catView = overlayWindow.catView
        catView.onRequestPermission = { [weak self] in
            self?.openInputMonitoringSettings()
        }
        catView.onRightClickMenu = { [weak self] _ in
            guard let self, !self.isMenuTracking else { return nil }
            self.contextMenu = self.buildMenu()
            return self.contextMenu
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        renderTimer?.invalidate()
        if let observer = screenObserver { NotificationCenter.default.removeObserver(observer) }
        InputEngine.shared.flushStats()
        InputEngine.shared.stop()
    }

    // MARK: - 60 FPS Render Loop

    func startRenderLoop() {
        lastFrameTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self, self.isPetVisible else { return }
            let now = CACurrentMediaTime()
            let dt = CGFloat(now - self.lastFrameTime)
            self.lastFrameTime = now

            let view = self.overlayWindow.catView
            if self.isMenuTracking {
                InputEngine.shared.pollMouse(dt: min(dt, 1.0/25.0))
                return
            }
            view.physics.step(dt: dt, windowFrameInScreen: self.overlayWindow.frame)
            view.updateHoverAndClickThrough()
            view.needsDisplay = true
            self.writeRuntimeDiagnostics()
        }
        RunLoop.main.add(timer, forMode: .common)
        renderTimer = timer
    }

    // Opt-in developer probe of THIS GUI process; no key labels or typed text are stored.
    private func writeRuntimeDiagnostics(force:Bool=false) {
        guard CommandLine.arguments.contains("--diagnostics"),let view=overlayWindow?.catView else { return }
        let now=CACurrentMediaTime()
        guard force || now-lastDiagnosticTime>1 else { return }
        lastDiagnosticTime=now
        var info=InputEngine.shared.diagnosticSnapshot
        info["pid"]=ProcessInfo.processInfo.processIdentifier
        info["menuTracking"]=isMenuTracking
        info["petVisible"]=isPetVisible
        info["windowVisible"]=overlayWindow.isVisible
        info["bubblesEnabled"]=CatSettings.shared.showKeyBadges
        info["bubbleCount"]=view.physics.floatingKeycaps.count
        info["mousePaw"]=[view.physics.deskMouse.point.x,view.physics.deskMouse.point.y]
        info["gaze"]=[view.physics.eyeGaze.point.x,view.physics.eyeGaze.point.y]
        info["timestamp"]=Date().timeIntervalSince1970
        let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("KuroCat")
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        if let data=try? JSONSerialization.data(withJSONObject:info,options:[.prettyPrinted,.sortedKeys]) {
            try? data.write(to:folder.appendingPathComponent("runtime-status.json"),options:.atomic)
        }
    }

    // MARK: - Menu Bar Icon & Menu

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = makeMenuBarCatIcon()
            button.toolTip = "KuroCat 黑猫键盘桌宠"
        }
        statusItem.menu = buildMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !isMenuTracking else { return }
        let engine = InputEngine.shared
        let settings = CatSettings.shared
        let physics = overlayWindow.catView.physics
        func refresh(_ menu: NSMenu) {
            for item in menu.items {
                if item.tag == 1 {
                    let needs = engine.status == .needsPermission
                    item.title = "\(needs ? "⚠️" : "🟢") \(engine.status.rawValue)"
                    item.action = needs ? #selector(openInputMonitoringSettings) : nil
                    item.isEnabled = needs
                } else if item.tag == 2 {
                    item.title = "⌨️ 今日击键 \(engine.totalKeystrokesToday)  ·  KPM \(engine.currentKPM)  ·  摸猫 \(physics.totalPetSessions) 次"
                } else if item.tag == 3 {
                    item.isHidden = engine.status != .needsPermission
                }
                if item.action == #selector(toggleVisibility) {
                    item.title = isPetVisible ? "隐藏小黑猫" : "显示小黑猫"
                } else if item.action == #selector(toggleClickThrough) {
                    item.state = settings.fullClickThrough ? .on : .off
                } else if item.action == #selector(toggleFullScreenOverlay) {
                    item.state = settings.fullScreenOverlay ? .on : .off
                } else if item.action == #selector(toggleAutoStart) {
                    item.state = isAutoStartEnabled() ? .on : .off
                } else if item.action == #selector(toggleKeyBadges) {
                    item.state = settings.showKeyBadges ? .on : .off
                } else if item.action == #selector(togglePetInteraction) {
                    item.state = settings.petInteraction ? .on : .off
                } else if item.action == #selector(toggleCustomAutoActions) {
                    item.state = settings.customAutoActions ? .on : .off
                } else if item.action == #selector(selectScale(_:)), let value = item.representedObject as? NSNumber {
                    item.state = abs(settings.scale-CGFloat(value.doubleValue)) < 0.05 ? .on : .off
                } else if item.action == #selector(playCustomPose(_:)), let raw = item.representedObject as? String {
                    item.state = physics.customAction?.rawValue == raw ? .on : .off
                }
                if let submenu = item.submenu { refresh(submenu) }
            }
        }
        refresh(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        trackingMenus.insert(ObjectIdentifier(menu))
        overlayWindow.catView.setMenuTracking(true)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard trackingMenus.remove(ObjectIdentifier(menu)) != nil else { return }
        guard !isMenuTracking else { return }
        lastFrameTime = CACurrentMediaTime()
        // Release any paw held before opening the menu: the matching release may
        // have belonged to the menu itself and was deliberately ignored.
        overlayWindow.catView.physics.triggerMouseClick(button: 0, isDown: false)
        overlayWindow.catView.physics.triggerMouseClick(button: 1, isDown: false)
        overlayWindow.catView.setMenuTracking(false)
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let engine = InputEngine.shared
        let settings = CatSettings.shared
        let physics = overlayWindow.catView.physics

        // Status header
        let statusPrefix = engine.status == .needsPermission ? "⚠️" : "🟢"
        let statusItem = NSMenuItem(title: "\(statusPrefix) \(engine.status.rawValue)", action: engine.status == .needsPermission ? #selector(openInputMonitoringSettings) : nil, keyEquivalent: "")
        statusItem.target = self
        statusItem.tag = 1
        statusItem.isEnabled = engine.status == .needsPermission
        menu.addItem(statusItem)

        do {
            let grantItem = NSMenuItem(title: "🔑 前往系统设置开启「输入监控」...", action: #selector(openInputMonitoringSettings), keyEquivalent: "")
            grantItem.target = self
            grantItem.tag = 3
            grantItem.isHidden = engine.status != .needsPermission
            menu.addItem(grantItem)
        }

        // Live stats
        let statsTitle = "⌨️ 今日击键 \(engine.totalKeystrokesToday)  ·  KPM \(engine.currentKPM)  ·  摸猫 \(physics.totalPetSessions) 次"
        let statsItem = NSMenuItem(title: statsTitle, action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        statsItem.tag = 2
        menu.addItem(statsItem)

        menu.addItem(.separator())

        // Visibility & Interactive modes
        let visItem = NSMenuItem(title: isPetVisible ? "隐藏小黑猫" : "显示小黑猫", action: #selector(toggleVisibility), keyEquivalent: "")
        visItem.target = self
        menu.addItem(visItem)

        let clickThroughItem = NSMenuItem(title: "鼠标穿透（⌥ 临时操作）", action: #selector(toggleClickThrough), keyEquivalent: "")
        clickThroughItem.target = self
        clickThroughItem.state = settings.fullClickThrough ? .on : .off
        menu.addItem(clickThroughItem)

        let fullscreenItem = NSMenuItem(title: "全屏游戏/应用置顶显示", action: #selector(toggleFullScreenOverlay), keyEquivalent: "")
        fullscreenItem.target = self
        fullscreenItem.state = settings.fullScreenOverlay ? .on : .off
        menu.addItem(fullscreenItem)

        let autoStartItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleAutoStart), keyEquivalent: "")
        autoStartItem.target = self
        autoStartItem.state = isAutoStartEnabled() ? .on : .off
        menu.addItem(autoStartItem)

        menu.addItem(.separator())

        // Features
        let badgesItem = NSMenuItem(title: "显示按键气泡", action: #selector(toggleKeyBadges), keyEquivalent: "")
        badgesItem.target = self
        badgesItem.state = settings.showKeyBadges ? .on : .off
        menu.addItem(badgesItem)


        let petItem = NSMenuItem(title: "摸头/摸背闭眼互动", action: #selector(togglePetInteraction), keyEquivalent: "")
        petItem.target = self
        petItem.state = settings.petInteraction ? .on : .off
        menu.addItem(petItem)

        menu.addItem(.separator())

        // Scale submenu
        let scaleMenu = NSMenu()
        let scales: [(String, CGFloat)] = [
            ("迷你 (0.65x)", 0.65),
            ("偏小 (0.85x)", 0.85),
            ("标准 (1.0x)", 1.0),
            ("偏大 (1.25x)", 1.25),
            ("超大 (1.5x)", 1.5)
        ]
        for (title, val) in scales {
            let item = NSMenuItem(title: title, action: #selector(selectScale(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: Double(val))
            item.state = abs(settings.scale - val) < 0.05 ? .on : .off
            scaleMenu.addItem(item)
        }
        let scaleParent = NSMenuItem(title: "尺寸大小", action: nil, keyEquivalent: "")
        scaleParent.submenu = scaleMenu
        menu.addItem(scaleParent)

        if settings.coatTheme == .customTuxedo {
            let actions = NSMenu()
            for action in CustomCatAction.allCases {
                let item = NSMenuItem(title: action.rawValue, action: #selector(playCustomPose(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = action.rawValue
                item.state = physics.customAction == action ? .on : .off
                actions.addItem(item)
            }
            actions.addItem(.separator())
            let automatic = NSMenuItem(title: "闲置时自动播放", action: #selector(toggleCustomAutoActions), keyEquivalent: "")
            automatic.target = self
            automatic.state = settings.customAutoActions ? .on : .off
            actions.addItem(automatic)
            let reset = NSMenuItem(title: "恢复打字互动", action: #selector(resetCustomPose), keyEquivalent: "")
            reset.target = self
            actions.addItem(reset)
            let parent = NSMenuItem(title: "专属动作", action: nil, keyEquivalent: "")
            parent.submenu = actions
            menu.addItem(parent)
        }

        menu.addItem(.separator())

        let demoItem = NSMenuItem(title: "演示按键气泡与爪子动作", action: #selector(runDemoBurst), keyEquivalent: "")
        demoItem.target = self
        menu.addItem(demoItem)

        let resetPosItem = NSMenuItem(title: "重置位置到右下角", action: #selector(resetPosition), keyEquivalent: "")
        resetPosItem.target = self
        menu.addItem(resetPosItem)

        let relaunchItem = NSMenuItem(title: "重启 KuroCat (授权后刷新)", action: #selector(relaunchApp), keyEquivalent: "")
        relaunchItem.target = self
        menu.addItem(relaunchItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 KuroCat", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Actions

    @objc private func openInputMonitoringSettings() {
        InputEngine.shared.requestPermissionsAndOpenSettings()
    }

    private func showPet() {
        isPetVisible = true
        lastFrameTime = CACurrentMediaTime()
        overlayWindow.keepOnScreen()
        overlayWindow.orderFrontRegardless()
        overlayWindow.catView.updateHoverAndClickThrough()
        overlayWindow.catView.needsDisplay = true
    }

    @objc private func toggleVisibility() {
        if isPetVisible {
            isPetVisible = false
            overlayWindow.orderOut(nil)
        } else {
            showPet()
        }
    }

    @objc private func toggleClickThrough() {
        CatSettings.shared.fullClickThrough.toggle()
        overlayWindow.catView.updateHoverAndClickThrough()
    }

    @objc private func toggleFullScreenOverlay() {
        CatSettings.shared.fullScreenOverlay.toggle()
        overlayWindow.applyWindowLevelAndBehavior()
        if isPetVisible { overlayWindow.orderFrontRegardless() }
    }

    // MARK: - Launch at Login (macOS LaunchAgent — works reliably for signed & ad-hoc builds)

    private var launchAgentURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        return dir.appendingPathComponent("com.chanke.kurocat.plist")
    }

    private func isAutoStartEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    @discardableResult
    private func setAutoStartEnabled(_ enable: Bool) -> Bool {
        let fm = FileManager.default
        let url = launchAgentURL
        if enable {
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let appPath = Bundle.main.bundlePath
                let plist: [String: Any] = [
                    "Label": "com.chanke.kurocat",
                    "ProgramArguments": ["/usr/bin/open", "-a", appPath],
                    "RunAtLoad": true,
                    "KeepAlive": false
                ]
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: url, options: .atomic)
                return true
            } catch {
                return false
            }
        } else {
            do {
                if fm.fileExists(atPath: url.path) {
                    try fm.removeItem(at: url)
                }
                return true
            } catch {
                return false
            }
        }
    }

    @objc private func toggleAutoStart() {
        guard setAutoStartEnabled(!isAutoStartEnabled()) else {
            let alert = NSAlert()
            alert.messageText = "未能更新开机启动设置"
            alert.informativeText = "请检查 ~/Library/LaunchAgents 的访问权限后重试。"
            alert.runModal()
            return
        }
    }

    @objc private func toggleKeyBadges() {
        CatSettings.shared.showKeyBadges.toggle()
        overlayWindow.catView.needsDisplay = true
    }

    @objc private func toggleFootEgg() {
        CatSettings.shared.footEasterEgg.toggle()
    }

    @objc private func togglePetInteraction() {
        CatSettings.shared.petInteraction.toggle()
    }

    @objc private func selectScale(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        overlayWindow.applyScale(CGFloat(num.doubleValue))
        showPet()
    }

    @objc private func selectCoatTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let coat = CatCoatTheme(rawValue: raw) else { return }
        CatSettings.shared.coatTheme = coat
        // Auto-pair signature eye color (still freely overridable via 瞳色切换!)
        switch coat {
        case .classicBlack:
            CatSettings.shared.eyeTheme = .neonChartreuse
        case .siamese:
            CatSettings.shared.eyeTheme = .siameseBlue
        case .customTuxedo:
            CatSettings.shared.eyeTheme = .photoOlive
        case .shorthair, .orangeWhite:
            CatSettings.shared.eyeTheme = .softAmber
        }
    }

    @objc private func selectKeyboardTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let theme = KeyboardTheme(rawValue: raw) else { return }
        CatSettings.shared.keyboardTheme = theme
    }

    @objc private func selectEyeTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let theme = EyeColorTheme(rawValue: raw) else { return }
        CatSettings.shared.eyeTheme = theme
    }

    @objc private func resetPosition() {
        overlayWindow.resetPosition()
        showPet()
    }

    @objc private func playCustomPose(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = CustomCatAction(rawValue: raw) else { return }
        showPet()
        overlayWindow.catView.physics.playCustomAction(action, manual: true)
    }

    @objc private func toggleCustomAutoActions() {
        CatSettings.shared.customAutoActions.toggle()
        if !CatSettings.shared.customAutoActions { overlayWindow.catView.physics.cancelCustomAction() }
    }

    @objc private func resetCustomPose() {
        showPet()
        overlayWindow.catView.physics.cancelCustomAction()
    }

    @objc private func runDemoBurst() {
        showPet()
        let keys: [PhysicalKey] = [.w, .a, .s, .d, .f, .j, .o, .e, .space, .leftShift]
        for (idx, k) in keys.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(idx) * 0.13) { [weak self] in
                self?.overlayWindow.catView.physics.triggerKeyDown(k)
            }
        }
    }

    @objc private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, error in
            DispatchQueue.main.async {
                if let error {
                    let alert = NSAlert()
                    alert.messageText = "重启未成功"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Crisp Vector Menu Bar Cat Silhouette Icon

    private func makeMenuBarCatIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)

            // Cute cat head silhouette with ears
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 3.0, y: 8.5))
            path.addLine(to: CGPoint(x: 3.5, y: 2.5))
            path.addLine(to: CGPoint(x: 7.2, y: 6.0))
            path.addQuadCurve(to: CGPoint(x: 10.8, y: 6.0), control: CGPoint(x: 9.0, y: 5.5))
            path.addLine(to: CGPoint(x: 14.5, y: 2.5))
            path.addLine(to: CGPoint(x: 15.0, y: 8.5))
            path.addCurve(to: CGPoint(x: 9.0, y: 15.5), control1: CGPoint(x: 16.0, y: 12.8), control2: CGPoint(x: 13.0, y: 15.5))
            path.addCurve(to: CGPoint(x: 3.0, y: 8.5), control1: CGPoint(x: 5.0, y: 15.5), control2: CGPoint(x: 2.0, y: 12.8))
            path.closeSubpath()

            // Punch out cute cat eyes
            path.addEllipse(in: CGRect(x: 5.4, y: 8.8, width: 2.4, height: 2.2))
            path.addEllipse(in: CGRect(x: 10.2, y: 8.8, width: 2.4, height: 2.2))

            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)
            return true
        }
        img.isTemplate = true
        return img
    }
}
