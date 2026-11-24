import AppKit
import QuartzCore
import CoreGraphics
setbuf(stdout,nil)
if CommandLine.arguments.contains("--preference-probe") {
 print(CatSettings.shared.showKeyBadges ? "on" : "off")
 exit(0)
}
let out=CommandLine.arguments[1]
try! FileManager.default.createDirectory(atPath:out,withIntermediateDirectories:true)
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
let settings=CatSettings.shared
settings.coatTheme = .customTuxedo;settings.customAutoActions=false
let delegate=AppDelegate()
delegate.setupOverlay()
let window=app.windows.compactMap { $0 as? OverlayWindow }.first!
let view=window.catView, frame=window.frame
func pump(_ seconds:Double) {
 let until=Date(timeIntervalSinceNow:seconds)
 while Date()<until { RunLoop.current.run(until:Date(timeIntervalSinceNow:0.01)) }
}
func items(_ menu:NSMenu)->[NSMenuItem] { menu.items.flatMap { [$0]+($0.submenu.map(items) ?? []) } }
func item(_ selector:String,_ value:String?=nil)->NSMenuItem {
 items(delegate.buildMenu()).first { $0.action==NSSelectorFromString(selector) && (value==nil || ($0.representedObject as? String)==value!) }!
}
func invoke(_ entry:NSMenuItem) { precondition(app.sendAction(entry.action!,to:entry.target,from:entry)) }
func invoke(_ selector:String) { invoke(item(selector)) }
let displays=[CGRect(x:-1440,y:0,width:1440,height:875),CGRect(x:0,y:25,width:1440,height:875)]
for origin in [CGPoint(x:-2000,y:-300),CGPoint(x:-100,y:820),CGPoint(x:1400,y:880),CGPoint(x:3000,y:200)] {
 let result=OverlayWindow.fittedFrame(CGRect(origin:origin,size:CGSize(width:540,height:480)),visibleFrames:displays)
 precondition(displays.contains { $0.contains(result) },"Pet left off-screen: \(result)")
}
precondition(OverlayWindow.fittedFrame(CGRect(x:-1200,y:50,width:360,height:320),visibleFrames:displays).minX == -1200)
print("PASS: multi-display fitting, negative origins, off-screen recovery")
var menu=delegate.buildMenu()
for _ in 0..<30 {
 menu=delegate.buildMenu()
 let all=items(menu)
 precondition(all.filter { $0.action==NSSelectorFromString("toggleVisibility") }.count==1)
 precondition(all.filter { $0.action==NSSelectorFromString("playCustomPose:") }.count==5)
 for entry in all where entry.action != nil && entry.submenu == nil { precondition(entry.target === delegate && delegate.responds(to:entry.action!)) }
}
settings.showKeyBadges=false
UserDefaults.standard.synchronize()
let probe=Process(),pipe=Pipe()
probe.executableURL=URL(fileURLWithPath:CommandLine.arguments[0])
probe.arguments=["--preference-probe"];probe.standardOutput=pipe
try! probe.run();probe.waitUntilExit()
precondition(String(data:pipe.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8)!.trimmingCharacters(in:.whitespacesAndNewlines)=="off")
menu=delegate.buildMenu()
precondition(items(menu).first { $0.action==NSSelectorFromString("toggleKeyBadges") }!.state == .off)
invoke("toggleKeyBadges")
menu=delegate.buildMenu()
precondition(items(menu).first { $0.action==NSSelectorFromString("toggleKeyBadges") }!.state == .on)
precondition(UserDefaults.standard.bool(forKey:"KuroCat.ShowKeyBadges"))
print("PASS: 30 menu refreshes retain all actions; checkmarks match persisted state")
var controlClicks=0
let handler=view.onRightClickMenu
view.onRightClickMenu={ _ in controlClicks+=1;return nil }
let ctrl=NSEvent.mouseEvent(with:.leftMouseDown,location:NSPoint(x:120,y:120),modifierFlags:.control,
 timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
view.mouseDown(with:ctrl);view.mouseDragged(with:ctrl)
precondition(controlClicks==1 && window.frame==frame)
view.onRightClickMenu=handler
print("PASS: Control-click opens context route without dragging")
// Drag completion restores the arrow/hover cursor, even when released outside the pet.
let click=NSEvent.mouseEvent(with:.leftMouseDown,location:NSPoint(x:120,y:120),modifierFlags:[],
 timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
view.mouseDown(with:click)
precondition(NSCursor.current == NSCursor.closedHand)
view.mouseUp(with:click)
precondition(NSCursor.current != NSCursor.closedHand)
print("PASS: drag release does not leave the closed-hand cursor stuck")
delegate.startRenderLoop();pump(0.06)
for _ in 0..<10 {
 delegate.menuWillOpen(menu);delegate.menuWillOpen(menu)
 let before=view.physics.time
 for _ in 0..<10 { view.updateHoverAndClickThrough() }
 pump(0.05)
 precondition(delegate.isMenuTracking && view.isPresentingMenu && !window.ignoresMouseEvents)
 precondition(view.physics.time==before,"Pose/hit area changed during menu tracking")
 delegate.menuDidClose(menu);delegate.menuDidClose(menu)
 precondition(!delegate.isMenuTracking && !view.isPresentingMenu)
}
let before=view.physics.time;pump(0.06);precondition(view.physics.time>before)
print("PASS: repeated tracking freezes capture/animation; normal rendering resumes")
invoke("toggleVisibility");precondition(!window.isVisible)
invoke(item("playCustomPose:",CustomCatAction.wave.rawValue))
precondition(window.isVisible && view.physics.customAction == .wave && view.physics.isManualCustomAction)
let pose=view.physics,epoch=CACurrentMediaTime()
for n in 0..<90 {
 pose.step(dt:1/60,windowFrameInScreen:window.frame,scripted:ScriptedFrameInput(
 now:epoch+Double(n)/60,activeKeys:[.leftOption],orderedKeys:[.leftOption],mouseScreenPos:CGPoint(x:100,y:100),
 mouseVelocity:CGVector(dx:400,dy:100),leftMouseDown:false,rightMouseDown:false,
 lastMouseMoveTime:epoch+Double(n)/60,lastMouseClickTime:0,lastKeyActivityTime:epoch))
}
precondition(pose.customAction == .wave && pose.customDisplayedPose=="wave")
pose.triggerKeyDown(.d)
precondition(pose.customAction==nil && pose.floatingKeycaps.last?.label=="D")
invoke(item("playCustomPose:",CustomCatAction.nap.rawValue));pose.triggerMouseClick(button:0,isDown:true)
precondition(pose.customAction==nil);pose.triggerMouseClick(button:0,isDown:false)
print("PASS: manual pose survives pointer/held Option; new D/click restores interaction")
invoke("toggleVisibility");invoke("resetPosition");precondition(window.isVisible)
invoke("toggleVisibility")
let scale=item("selectScale:");scale.representedObject=NSNumber(value:1.5);invoke(scale)
precondition(window.isVisible && abs(window.frame.width-540)<0.01)
precondition(NSScreen.screens.contains { $0.visibleFrame.contains(window.frame) })
window.applyScale(.nan);precondition(window.frame.width==360)
settings.fullScreenOverlay=true
invoke("toggleFullScreenOverlay");precondition(window.level == .floating)
invoke("toggleFullScreenOverlay");precondition(window.level == .statusBar)
print("PASS: hidden reset/resize restore visibility; scaled frame stays on-screen; window level updates")
window.resetPosition()
let idlePose=pose.customAction
for n in 0..<3 {
 let event=NSEvent.mouseEvent(with:.rightMouseDown,location:NSPoint(x:180,y:180),modifierFlags:[],
 timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:n,clickCount:1,pressure:1)!
 let timer=Timer(timeInterval:0.25,repeats:false) { _ in
  precondition(delegate.isMenuTracking && view.isPresentingMenu && !window.ignoresMouseEvents)
  if n==0 {
   let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
   if let popup=windows.first(where:{ ($0[kCGWindowOwnerPID as String] as? Int32)==getpid() &&
                                        ($0[kCGWindowLayer as String] as? Int ?? 0)>25 }),
      let id=popup[kCGWindowNumber as String] as? Int {
    let capture=Process();capture.executableURL=URL(fileURLWithPath:"/usr/sbin/screencapture")
    capture.arguments=["-x","-o","-l",String(id),out+"/context-menu.png"]
    try? capture.run();capture.waitUntilExit()
   }
  }
  delegate.contextMenu.cancelTracking()
 }
 RunLoop.main.add(timer,forMode:.common)
 view.rightMouseDown(with:event)
 precondition(!delegate.isMenuTracking && !view.isPresentingMenu)
}

// Position, not just visibility: exercise real popup windows on every connected
// screen at all supported size extremes, with a snapshot of the click location.
let quartzTop=NSScreen.screens[0].frame.maxY
for (display,screen) in NSScreen.screens.enumerated() {
 for factor:CGFloat in [0.65,1,1.5] {
  window.applyScale(factor)
  window.setFrameOrigin(CGPoint(x:screen.visibleFrame.midX-window.frame.width/2,
                               y:screen.visibleFrame.midY-window.frame.height/2))
  let local=NSPoint(x:window.frame.width*0.55,y:window.frame.height*0.65)
  let screenPoint=window.convertPoint(toScreen:local)
  let expected=CGPoint(x:screenPoint.x,y:quartzTop-screenPoint.y)
  let event=NSEvent.mouseEvent(with:.rightMouseDown,location:local,modifierFlags:[],
    timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,
    context:nil,eventNumber:0,clickCount:1,pressure:1)!
  let check=Timer(timeInterval:0.15,repeats:false) { _ in
   let rows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
   let frames=rows.filter { ($0[kCGWindowOwnerPID as String] as? Int32)==getpid() &&
                              ($0[kCGWindowLayer as String] as? Int)==101 }.compactMap { row -> CGRect? in
      guard let bounds=row[kCGWindowBounds as String] as? [String:Any] else { return nil }
      return CGRect(dictionaryRepresentation:bounds as CFDictionary)
   }
   precondition(frames.contains { $0.insetBy(dx:-4,dy:-4).contains(expected) },
                "Popup jumped away from click: display=\(display), scale=\(factor), click=\(expected), menus=\(frames)")
   delegate.contextMenu.cancelTracking()
  }
  RunLoop.main.add(check,forMode:.common)
  view.rightMouseDown(with:event)
  precondition(!delegate.isMenuTracking)
  print("PASS: popup stays at click on display \(display), scale \(factor)")
 }
}
delegate.setupStatusItem()
let trayTimer=Timer(timeInterval:0.2,repeats:false) { _ in
 precondition(delegate.isMenuTracking,"Native status menu did not enter tracking")
 delegate.statusItem.menu!.cancelTracking()
}
RunLoop.main.add(trayTimer,forMode:.common)
delegate.statusItem.button!.performClick(nil)
precondition(!delegate.isMenuTracking)
NSStatusBar.system.removeStatusItem(delegate.statusItem)
print("PASS: native status-bar button opens and closes the same menu")
precondition(pose.customAction==idlePose)
print("PASS: 3 actual AppKit popup/cancel cycles return with capture and pose intact")
delegate.applicationWillTerminate(Notification(name:NSApplication.willTerminateNotification))
window.orderOut(nil)
print("PASS: UI interaction regression suite complete")
