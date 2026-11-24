import AppKit
import CoreGraphics
import QuartzCore
import ImageIO
import UniformTypeIdentifiers
setbuf(stdout,nil)
let out=URL(fileURLWithPath:CommandLine.arguments[1]);try! FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
let settings=CatSettings.shared
settings.coatTheme = .customTuxedo;settings.eyeTheme = .photoOlive;settings.showKeyBadges=true;settings.customAutoActions=false
let engine=InputEngine.shared
let p=CatPhysics()
var downs:[PhysicalKey]=[]
engine.onKeyDown={ key in downs.append(key);p.triggerKeyDown(key) }
for key in PhysicalKey.allCases {
 let before=downs.count
 engine.setKeyState(key,isDown:true,fromHID:true)
 engine.setKeyState(key,isDown:true,fromHID:false)
 precondition(downs.count == before+1,"Duplicate HID/tap bubble: \(key)")
 precondition(p.floatingKeycaps.last?.label == key.badgeLabel)
 engine.setKeyState(key,isDown:false,fromHID:true)
 engine.setKeyState(key,isDown:false,fromHID:false)
 precondition(!engine.activeKeys.contains(key))
}
precondition(engine.activeKeys.isEmpty)
// A dropped HID release used to leave this letter permanently held, suppressing later bubbles.
engine.setKeyState(.r,isDown:true,fromHID:true)
engine.setKeyState(.r,isDown:true,fromHID:false)
engine.setKeyState(.r,isDown:false,fromHID:false)
precondition(engine.activeKeys.isEmpty,"Missing HID-up leaves stale key state")
let retry=downs.count
engine.setKeyState(.r,isDown:true,fromHID:false)
precondition(downs.count==retry+1,"A released letter failed to bubble on the next press")
engine.setKeyState(.r,isDown:false,fromHID:false)
for code in UInt16(0)...UInt16(127) {
 let e=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:true)!
 let count=downs.count
 engine.handleCGEvent(type:.keyDown,event:e)
 precondition(downs.count==count+1,"CG key omitted: \(code)")
 engine.handleCGEvent(type:.keyUp,event:e)
}
print("PASS: missing HID-up recovery and all 128 CG keycodes reach actual bubble callbacks")
precondition(PhysicalKey.fromHIDUsage(0x59) == .num1 && PhysicalKey.fromCGKeyCode(83) == .num1)
precondition(PhysicalKey.fromHIDUsage(UInt32.max) == nil,"Array sentinel became a bubble key")
precondition(PhysicalKey.fromHIDUsage(0x07) == .d && PhysicalKey.fromHIDUsage(0x07)?.badgeLabel == "D")
precondition(PhysicalKey.fromHIDUsage(0xE8) == nil && PhysicalKey.fromHIDUsage(0xFFFF) == nil)
precondition(PhysicalKey.fromHIDUsage(0x01) == nil && PhysicalKey.fromHIDUsage(0x03) == nil)
print("PASS: D decodes to D; array/sentinel/error usages never produce HID FFFFFFFF bubbles")

precondition(PhysicalKey.fromHIDUsage(0x58) != .enter)
for usage in UInt32(4)...UInt32(0xE7) { precondition(PhysicalKey.fromHIDUsage(usage) != nil) }
for code in UInt16(0)...UInt16(127) { precondition(PhysicalKey.fromCGKeyCode(code) != nil) }
precondition(PhysicalKey.fromConsumerUsage(0xE9) == PhysicalKey.fromSystemKey(0))
let leftFlags=CGEventFlags(rawValue:CGEventFlags.maskShift.rawValue | 2)
let bothFlags=CGEventFlags(rawValue:CGEventFlags.maskShift.rawValue | 6)
precondition(engine.isModifierKeyDown(key:.leftShift,flags:bothFlags))
precondition(engine.isModifierKeyDown(key:.rightShift,flags:bothFlags))
precondition(!engine.isModifierKeyDown(key:.rightShift,flags:leftFlags))
let e=CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:true)!
engine.handleCGEvent(type:.keyDown,event:e)
let count=downs.count
e.setIntegerValueField(.keyboardEventAutorepeat,value:1)
engine.handleCGEvent(type:.keyDown,event:e)
precondition(downs.count == count+1 && engine.activeKeys == [.a])
engine.handleCGEvent(type:.keyUp,event:e)
precondition(engine.activeKeys.isEmpty)
print("PASS: \(PhysicalKey.allCases.count) named keys bubble once with HID/tap dedup; all HID/CG codes retained; numpad independent; consumer/media identity; sided modifiers; repeat animation")
let frame=CGRect(x:0,y:0,width:360,height:320),epoch=CACurrentMediaTime()
func tick(_ p:CatPhysics,_ t:Double,_ mouse:CGPoint,_ keys:[PhysicalKey]=[]) {
 p.step(dt:1/60,windowFrameInScreen:frame,scripted:ScriptedFrameInput(now:epoch+t,activeKeys:Set(keys),orderedKeys:keys,mouseScreenPos:mouse,mouseVelocity:.zero,leftMouseDown:false,rightMouseDown:false,lastMouseMoveTime:epoch+t,lastMouseClickTime:0,lastKeyActivityTime:keys.isEmpty ? 0 : epoch+t))
}
let rig=CatPhysics()
for i in 0..<60 {tick(rig,Double(i)/60,CGPoint(x:800,y:200))}
precondition(rig.deskMouse.point.x>4 && rig.eyeGaze.point.x>0.7)
// Typing must not steal gaze from the actual cursor.
rig.triggerKeyDown(.a)
for i in 60..<120 {tick(rig,Double(i)/60,CGPoint(x:-800,y:200),[.a])}
precondition(rig.deskMouse.point.x < -4 && rig.eyeGaze.point.x < -0.7)
precondition(abs(rig.deskMouse.point.x)<=14.1 && abs(rig.deskMouse.point.y)<=7.1)
print("PASS: cursor position drives bounded mouse paw and eyes, including during typing")
let corner=CatPhysics()
func track(_ x:CGFloat,_ t:Double) {
 var input=ScriptedFrameInput(now:epoch+t,activeKeys:[],orderedKeys:[],mouseScreenPos:CGPoint(x:x,y:450),mouseVelocity:.zero,leftMouseDown:false,rightMouseDown:false,lastMouseMoveTime:epoch+t,lastMouseClickTime:0,lastKeyActivityTime:0)
 input.trackingScreen=CGRect(x:0,y:0,width:1440,height:900)
 corner.step(dt:1/60,windowFrameInScreen:CGRect(x:1080,y:0,width:360,height:320),scripted:input)
}
for i in 0..<60 {track(200,Double(i)/60)}
let first=corner.deskMouse.point.x
for i in 60..<120 {track(900,Double(i)/60)}
precondition(first < -9 && corner.deskMouse.point.x > 3,"Mouse paw saturates when both cursor positions are far left of cat")
print("PASS: whole-screen pointer mapping remains visible away from the cat")

func save(_ im:CGImage,_ name:String) {
 try! NSBitmapImageRep(cgImage:im).representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(name))
}
func pixels(_ im:CGImage,_ rect:CGRect)->Data {
 let crop=im.cropping(to:rect)!
 let c=CGContext(data:nil,width:crop.width,height:crop.height,bitsPerComponent:8,bytesPerRow:crop.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 c.draw(crop,in:CGRect(x:0,y:0,width:crop.width,height:crop.height))
 return Data(bytes:c.data!,count:crop.width*crop.height*4)
}
precondition(DeskCatArtwork.images.count==6)
// All six scenes must be real cutouts, not opaque panels disguised by a light fill.
for id in DeskCatArtwork.sceneIDs {
 let image=DeskCatArtwork.images[id]!
 let bitmap=NSBitmapImageRep(cgImage:image)
 precondition(bitmap.colorAt(x:20,y:20)!.alphaComponent < 0.01,"Opaque background in \(id)")
 let empty=DeskCatArtwork.canvas(CGPoint(x:20,y:60))
 precondition(CatRenderer.hitTest(point:empty,physics:CatPhysics(),showPermissionPill:false) == .none,"Transparent area blocks desktop")
}
precondition(CatRenderer.hitTest(point:CGPoint(x:180,y:308),physics:CatPhysics(),showPermissionPill:true) == .none,"Hidden banner intercepts desktop")
print("PASS: six genuinely transparent sprites; empty-area and hidden-banner click-through")

let a=CatPhysics(),b=CatPhysics()
a.eyeGaze.x.value = -0.85;b.eyeGaze.x.value = 0.85
a.deskMouse.x.value = -14;b.deskMouse.x.value = 14
let ia=DeskCatArtwork.animatedImage("sit_base",physics:a)!,ib=DeskCatArtwork.animatedImage("sit_base",physics:b)!
// CGImage crop coordinates are top-down; head/neck outside irises must be pixel-identical.
precondition(pixels(ia,CGRect(x:265,y:150,width:30,height:145)) == pixels(ib,CGRect(x:265,y:150,width:30,height:145)),"Head/neck moved")
precondition(pixels(ia,CGRect(x:238,y:120,width:85,height:30)) != pixels(ib,CGRect(x:238,y:120,width:85,height:30)),"Eyes do not follow")
precondition(pixels(ia,CGRect(x:319,y:285,width:90,height:93)) != pixels(ib,CGRect(x:319,y:285,width:90,height:93)),"Mouse/paw does not follow")
save(ia,"look-left.png");save(ib,"look-right.png")
precondition(pixels(ia,CGRect(x:95,y:355,width:35,height:15)) == pixels(ib,CGRect(x:95,y:355,width:35,height:15)),"Table moves with mouse")
precondition(pixels(ia,CGRect(x:420,y:355,width:25,height:15)) == pixels(ib,CGRect(x:420,y:355,width:25,height:15)),"Table moves with mouse")
let lp=[UInt8](pixels(ia,CGRect(x:330-14,y:297,width:35,height:18)))
let rp=[UInt8](pixels(ib,CGRect(x:330+14,y:297,width:35,height:18)))
let error=zip(lp,rp).map { abs(Int($0)-Int($1)) }.reduce(0,+)
precondition(Double(error)/Double(lp.count)<3.0,"Mouse paw texture stretches between positions")
print("PASS: wider mouse travel preserves original paw texture and stationary desktop")

for action in CustomCatAction.allCases {
 let p=CatPhysics();p.playCustomAction(action)
 for i in 0..<60 {tick(p,Double(i)/60,CGPoint(x:180,y:180))}
 let rect=DeskCatArtwork.headRect(p.customDisplayedPose)
 precondition(CatRenderer.hitTest(point:CGPoint(x:rect.midX,y:rect.midY),physics:p,showPermissionPill:false) == .head)
 p.triggerKeyDown(.numEnter)
 precondition(p.customAction == nil && p.floatingKeycaps.last?.label == "Num ↵")
 for i in 60..<90 {tick(p,Double(i)/60,CGPoint(x:180,y:180))}
 precondition(p.customDisplayedPose == "sit_base" && p.customPoseOpacity>0.99)
}
print("PASS: six scene assets; fixed head/neck; actual iris/paw pixel changes; five idle scenes wake and remain interactive")
func render(_ p:CatPhysics)->CGImage {
 let c=CGContext(data:nil,width:720,height:640,bitsPerComponent:8,bytesPerRow:720*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 c.translateBy(x:0,y:640);c.scaleBy(x:2,y:-2)
 CatRenderer.draw(in:c,physics:p,showPermissionPill:false)
 return c.makeImage()!
}
let gif=CGImageDestinationCreateWithURL(out.appendingPathComponent("desk-live.gif") as CFURL,UTType.gif.identifier as CFString,150,nil)!
CGImageDestinationSetProperties(gif,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
let live=CatPhysics()
for n in 0..<150 {
 let t=Double(n)/15
 let key:PhysicalKey = [.a,.space,.leftShift,.f12,.num7,.arrowUp,.volumeUp][(n/6)%7]
 if n<60 && n%6==0 {live.triggerKeyDown(key,at:epoch+t)}
 for j in 0..<4 {
  tick(live,t+Double(j)/60,CGPoint(x:180+400*sin(t*1.5),y:190+260*cos(t*1.2)))
 }
 if n==110 {live.triggerMouseClick(button:0,isDown:true)}
 if n==113 {live.triggerMouseClick(button:0,isDown:false)}
 let im=render(live)
 CGImageDestinationAddImage(gif,im,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:1.0/15]] as CFDictionary)
 if [10,50,95,112].contains(n) {save(im,"runtime-\(n).png")}
}
precondition(CGImageDestinationFinalize(gif))
let start=CACurrentMediaTime()
for _ in 0..<60 {_=DeskCatArtwork.animatedImage("sit_base",physics:live)}
print(String(format:"Desk rendering %.2f ms/frame (60-frame sample)",(CACurrentMediaTime()-start)/60*1000))
print("PASS: exported 150-frame animation from production renderer")
