import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

setbuf(stdout, nil)
let output = URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
let settings=CatSettings.shared
let oldCoat=settings.coatTheme, oldEye=settings.eyeTheme, oldAuto=settings.customAutoActions
let oldBadges=settings.showKeyBadges
defer {
 settings.coatTheme=oldCoat;settings.eyeTheme=oldEye
 settings.customAutoActions=oldAuto;settings.showKeyBadges=oldBadges
}
settings.coatTheme = .customTuxedo
settings.eyeTheme = .photoOlive
settings.customAutoActions = false
settings.showKeyBadges = true
let epoch=CACurrentMediaTime()
let window=CGRect(x:0,y:0,width:360,height:320)
func input(_ time:Double,keys:[PhysicalKey]=[],velocity:CGVector = .zero,lastKey:Double=0,lastMove:Double=0)->ScriptedFrameInput {
 ScriptedFrameInput(now:epoch+time,activeKeys:Set(keys),orderedKeys:keys,
  mouseScreenPos:CGPoint(x:185,y:180),mouseVelocity:velocity,
  leftMouseDown:false,rightMouseDown:false,
  lastMouseMoveTime:lastMove > 0 ? epoch+lastMove : 0,
  lastMouseClickTime:0,lastKeyActivityTime:lastKey > 0 ? epoch+lastKey : 0)
}
func advance(_ p:CatPhysics,_ seconds:Double,from start:Double=0,velocity:CGVector = .zero) {
 for i in 0..<Int(seconds*60) {
  p.step(dt:1.0/60,windowFrameInScreen:window,
   scripted:input(start+Double(i)/60,velocity:velocity))
 }
}
let controller=CatPhysics()
controller.playCustomAction(.nap);advance(controller,1)

precondition(controller.customNap.value > 0.95,"Nap did not settle")
controller.triggerKeyDown(.a,at:epoch+2)
precondition(controller.customAction == nil,"Typing must interrupt the special action")
advance(controller,1,from:2)
precondition(controller.customNap.value < 0.02,"Wake transition did not settle")
controller.playCustomAction(.belly);advance(controller,1,from:4,velocity:CGVector(dx:120,dy:0))
precondition(controller.customAction == nil,"Mouse motion must interrupt after menu grace")
controller.playCustomAction(.groom);controller.triggerMouseClick(button:0,isDown:true)
precondition(controller.customAction == nil,"Mouse click must interrupt immediately")
controller.playCustomAction(.belly);controller.registerPetStroke(canvasPoint:CGPoint(x:184,y:160),delta:16,isHead:true,at:epoch+6)
precondition(controller.customAction == nil,"Petting must interrupt")
let automatic=CatPhysics()
settings.customAutoActions=true;advance(automatic,21)
precondition(automatic.customAction != nil,"Idle should schedule a special action")
automatic.triggerKeyDown(.j,at:epoch+22)
advance(automatic,1,from:22)
precondition(automatic.customAction == nil,"Idle action should not restart immediately after input")
settings.customAutoActions=false
let off=CatPhysics();advance(off,25)
precondition(off.customAction == nil,"Disabled automatic actions should remain disabled")
settings.coatTheme = .classicBlack
let legacy=CatPhysics();legacy.playCustomAction(.groom);advance(legacy,1)
precondition(legacy.customAction == nil && legacy.customGroom.value < 0.02,"Custom actions must not affect other skins")
settings.coatTheme = .customTuxedo
print("PASS: pose settling, typing/mouse/petting wake, idle cooldown, auto toggle, old-skin isolation")

func render(_ p:CatPhysics,scale:Int=2)->CGImage {
 let w=360*scale,h=320*scale
 let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
  space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 c.setFillColor(NSColor(calibratedRed:0.89,green:0.90,blue:0.87,alpha:1).cgColor)
 c.fill(CGRect(x:0,y:0,width:w,height:h))
 c.translateBy(x:0,y:CGFloat(h));c.scaleBy(x:CGFloat(scale),y:-CGFloat(scale))
 CatRenderer.draw(in:c,physics:p,showPermissionPill:false)
 return c.makeImage()!
}
func save(_ im:CGImage,_ filename:String) {
 let rep=NSBitmapImageRep(cgImage:im)
 try! rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(filename))
}
precondition(CustomCatArtwork.images.count == 24,"All approved sprite cells must load")
// Whole-body mapping must preserve the supplied aspect ratio, with a single grounded pose.
for id in ["sit_base","rest_side","belly_hug","groom_leg"] {
 let image=CustomCatArtwork.images[id]!,rect=CustomCatArtwork.poseRect(id)
 precondition(abs(rect.width/rect.height-CGFloat(image.width)/CGFloat(image.height)) < 0.000001)
 precondition(abs(rect.maxY-258) < 0.000001)
}
let change=CatPhysics();change.playCustomAction(.groom)
for i in 0..<60 {
 change.step(dt:1.0/60,windowFrameInScreen:window,scripted:input(Double(i)/60))
 precondition(change.customDisplayedPose == "sit_base" || change.customDisplayedPose == "groom_leg")
 precondition(change.customPoseOpacity >= 0 && change.customPoseOpacity <= 1)
}
precondition(change.customDisplayedPose == "groom_leg" && change.customPoseOpacity > 0.99)
// Check the actual deformation backend, not only the pose controller.
let motionProbe=CatPhysics()
let still=CustomCatArtwork.animatedImage("sit_base",physics:motionProbe)!
advance(motionProbe,0.6)
let moving=CustomCatArtwork.animatedImage("sit_base",physics:motionProbe)!
precondition(still.dataProvider!.data! as Data != moving.dataProvider!.data! as Data,
             "Whole-image motion backend is inactive; static fallback would hide this failure")
save(still,"cat-open.png");save(moving,"cat-motion.png")
for _ in 0..<3 { motionProbe.registerPetStroke(canvasPoint:CGPoint(x:184,y:120),delta:20,isHead:true,at:epoch+0.6) }
precondition(motionProbe.effectiveEyeClosure > 0.95)
save(CustomCatArtwork.animatedImage("sit_base",physics:motionProbe)!,"cat-closed.png")
let benchmarkStart=CACurrentMediaTime()
for _ in 0..<30 { _=CustomCatArtwork.animatedImage("groom_leg",physics:motionProbe) }
print(String(format:"Whole-pose rendering: %.2f ms/frame (30-frame sample)",(CACurrentMediaTime()-benchmarkStart)/30*1000))
print("PASS: whole-pose aspect ratio, grounded feet, one-pose transitions, live deformation backend")
let p=CatPhysics()
var captures:[CGImage]=[]
let gifURL=output.appendingPathComponent("custom-cat-live.gif")
let fps=15,frameCount=195
let gif=CGImageDestinationCreateWithURL(gifURL as CFURL,UTType.gif.identifier as CFString,frameCount,nil)!
CGImageDestinationSetProperties(gif,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
var lastKey:Double=0
for frame in 0..<frameCount {
 let t=Double(frame)/Double(fps)
 if frame == 38 {p.playCustomAction(.nap,duration:2.7)}
 if frame == 83 {p.playCustomAction(.belly,duration:2.7)}
 if frame == 128 {p.playCustomAction(.groom,duration:2.7)}
 let typing=frame < 33 || frame >= 175
 for step in 0..<4 {
  let now=t+Double(step)/60
  let keys:[PhysicalKey] = typing ? (frame%8 < 4 ? [.a] : [.j]) : []
  if typing && step == 0 && frame%2 == 0 {
   lastKey=now;p.triggerKeyDown(keys[0],at:epoch+now)
  }
  p.step(dt:1.0/60,windowFrameInScreen:window,scripted:input(now,keys:keys,lastKey:lastKey))
 }
 let im=render(p,scale:1)
 CGImageDestinationAddImage(gif,im,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:1.0/Double(fps)]] as CFDictionary)
 if [14,65,110,154].contains(frame) {
  settings.showKeyBadges=false
  captures.append(render(p));save(render(p),"state-\(captures.count).png")
  settings.showKeyBadges=true
 }
}
precondition(CGImageDestinationFinalize(gif),"GIF export failed")
precondition(captures.count == 4)
for a in 0..<4 {for b in 0..<a {
 precondition(captures[a].dataProvider!.data! as Data != captures[b].dataProvider!.data! as Data,"Distinct actions rendered the same frame")
}}
// Validate custom head/body hit zones after the rig settles into each action.
for action in CustomCatAction.allCases {
 let rig=CatPhysics();rig.playCustomAction(action);advance(rig,1)
 let head=DeskCatArtwork.headRect(rig.customDisplayedPose)
 precondition(CatRenderer.hitTest(point:CGPoint(x:head.midX,y:head.midY),physics:rig,showPermissionPill:false) == .head,"Special pose head not interactive")
}
let sheet=CGContext(data:nil,width:1440,height:1280,bitsPerComponent:8,bytesPerRow:1440*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
for (i,im) in captures.enumerated() {
 let x=(i%2)*720,y=(1-i/2)*640
 sheet.draw(im,in:CGRect(x:x,y:y,width:720,height:640))
}
save(sheet.makeImage()!,"custom-cat-actions.png")
print("PASS: four distinct sprite action captures, three pose hit zones, exported 195-frame live GIF")
