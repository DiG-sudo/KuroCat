import AppKit
import CoreGraphics
import QuartzCore
import ImageIO
import UniformTypeIdentifiers
setbuf(stdout,nil)
let root=URL(fileURLWithPath:CommandLine.arguments[1]),output=URL(fileURLWithPath:CommandLine.arguments[2])
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
CatSettings.shared.coatTheme = .customTuxedo
CatSettings.shared.customAutoActions = false
CatSettings.shared.showKeyBadges = true
func pixels(_ image:CGImage,_ rect:CGRect)->Data {
 let crop=image.cropping(to:rect)!,w=Int(rect.width),h=Int(rect.height)
 let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 c.draw(crop,in:CGRect(origin:.zero,size:rect.size));return Data(bytes:c.data!,count:w*h*4)
}
func save(_ image:CGImage,_ name:String) {
 let d=CGImageDestinationCreateWithURL(output.appendingPathComponent(name+".png") as CFURL,UTType.png.identifier as CFString,1,nil)!
 CGImageDestinationAddImage(d,image,nil);precondition(CGImageDestinationFinalize(d))
}
let poses:[(String,String,CGFloat)] = [("wave","wave",1),("rest_side","nap",1),("belly_hug","belly",2),("groom_leg","groom",0.84),("observe","observe",1.48)]
for (id,name,age) in poses {
 let actual=DeskCatIdleAnimation.image(id,age:age)!
 let reference=NSImage(contentsOf:root.appendingPathComponent("tests/idle/fixtures/"+name+".png"))!.cgImage(forProposedRect:nil,context:nil,hints:nil)!
 let r=CGRect(x:0,y:0,width:512,height:460),a=[UInt8](pixels(actual,r)),b=[UInt8](pixels(reference,r))
 let error=zip(a,b).reduce(0) { $0+abs(Int($1.0)-Int($1.1)) }
 let mean=Double(error)/Double(a.count)
 precondition(mean<0.01,"Approved pose differs: \(id), mean error \(mean)")
 save(actual,name)
 print(String(format:"PASS approved %@: %.4f mean pixel error",id,mean))
}
let fixed:[String:[CGRect]] = [
 "wave":[CGRect(x:204,y:45,width:131,height:134),CGRect(x:50,y:305,width:385,height:100)],
 "rest_side":[CGRect(x:0,y:0,width:255,height:460),CGRect(x:341,y:0,width:171,height:460),CGRect(x:255,y:245,width:86,height:215)],
 "groom_leg":[CGRect(x:0,y:0,width:512,height:250),CGRect(x:0,y:284,width:512,height:176),CGRect(x:0,y:250,width:214,height:34),CGRect(x:240,y:250,width:272,height:34)]
]
for (id,regions) in fixed {
 let first=DeskCatIdleAnimation.image(id,age:0)!,baseline=regions.map { pixels(first,$0) }
 for n in 0..<150 {autoreleasepool {
  let image=DeskCatIdleAnimation.image(id,age:CGFloat(n)/25)!
  for (r,b) in zip(regions,baseline) {precondition(pixels(image,r)==b,"Neighbouring body pixels moved: \(id), frame \(n)")}
 }}
 print("PASS \(id): protected face/body pixels unchanged throughout the complete cycle")
}
// A lower-lip mask previously hid the tongue until it was below the mouth.
let tongue=NSBitmapImageRep(cgImage:DeskCatIdleAnimation.image("groom_leg",age:0.84)!)
var pink:[CGPoint]=[]
for y in 250..<282 {for x in 214..<240 {
 if let c=tongue.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),c.redComponent>0.65,c.redComponent-c.greenComponent>0.15,abs(c.greenComponent-c.blueComponent)<0.08 {pink.append(CGPoint(x:x,y:y+40))}
}}
precondition(pink.count>20 && pink.map(\.y).min()! <= 293,"Visible tongue root is below the middle of the mouth")
print("PASS tongue visibly begins at the mouth junction, not below the lower lip")
// Pupil motion is confined to the irises, with the complete head and cheek unchanged.
for id in ["wave","belly_hug","observe"] {
 let a=DeskCatIdleAnimation.image(id,age:0.2,gaze:CGPoint(x:-1,y:0))!,b=DeskCatIdleAnimation.image(id,age:0.2,gaze:CGPoint(x:1,y:0))!
 let iris:CGRect
 switch id {case "wave":iris=CGRect(x:206,y:105,width:70,height:46)
 case "belly_hug":iris=CGRect(x:296,y:87,width:78,height:54)
 default:iris=CGRect(x:291,y:107,width:30,height:29)}
 precondition(pixels(a,iris) != pixels(b,iris),"Idle pupils stopped following: \(id)")
 precondition(pixels(a,CGRect(x:255,y:245,width:70,height:90))==pixels(b,CGRect(x:255,y:245,width:70,height:90)),"Idle gaze moved body: \(id)")
}
print("PASS idle eye tracking moves clipped pupils without moving the body")

// Reproduce the reported fake profile eye: no gaze direction may paint outside
// the actual iris or spill yellow onto the white face marking.
for id in ["wave","observe"] {
 let reference=NSBitmapImageRep(cgImage:DeskCatIdleAnimation.image(id,age:0)!)
 let allowed:[CGRect] = id=="wave" ? [CGRect(x:206,y:109,width:25,height:24),CGRect(x:249,y:126,width:30,height:26)] : [CGRect(x:290,y:102,width:20,height:26)]
 for gaze in [CGPoint(x:-1,y:-1),CGPoint(x:1,y:1),CGPoint(x:-1,y:1),CGPoint(x:1,y:-1)] {
  let actual=NSBitmapImageRep(cgImage:DeskCatIdleAnimation.image(id,age:0,gaze:gaze)!)
  for y in 40..<200 {for x in 180..<345 where !allowed.contains(where:{$0.contains(CGPoint(x:x,y:y))}) {
   precondition(reference.colorAt(x:x,y:y)==actual.colorAt(x:x,y:y),"Gaze changed original eye shape / face: \(id) at \(x),\(y)")
  }}
 }
 print("PASS \(id): all four gaze extremes preserve the original eye outline and white face marking")
}

let epoch=CACurrentMediaTime(),window=CGRect(x:0,y:0,width:360,height:320),cat=CatPhysics()
func tick(_ n:Int) {cat.step(dt:1/60,windowFrameInScreen:window,scripted:ScriptedFrameInput(now:epoch+Double(n)/60,activeKeys:[],orderedKeys:[],mouseScreenPos:CGPoint(x:180,y:180),mouseVelocity:.zero,leftMouseDown:false,rightMouseDown:false,lastMouseMoveTime:epoch+Double(n)/60,lastMouseClickTime:0,lastKeyActivityTime:0))}
for n in 0..<420 {tick(n)}
cat.playCustomAction(.groom,duration:60,manual:true)
for n in 420..<445 {tick(n)}
precondition(cat.customDisplayedPose=="groom_leg" && cat.customPoseAge<0.35,"Idle cycle used process uptime instead of action entry time")
precondition(DeskCatArtwork.animatedImage(cat.customDisplayedPose,physics:cat) != nil)
cat.triggerKeyDown(.d,at:epoch+8)
precondition(cat.customAction==nil && cat.floatingKeycaps.last?.label=="D")
for n in 445..<475 {tick(n)}
precondition(cat.customDisplayedPose=="sit_base")
cat.playCustomAction(.wave,manual:true);cat.triggerMouseClick(button:0,isDown:true)
precondition(cat.customAction==nil)
print("PASS selected actions start their own clock; keyboard D bubbles and mouse clicks return to the interactive desk")
// Idle scheduling must keep playing complete poses without a desk/cooldown gap.
CatSettings.shared.customAutoActions = true
let idleCat=CatPhysics()
func idleTick(_ subject:CatPhysics,_ frame:Int,velocity:CGVector = .zero,keys:Set<PhysicalKey> = [],mouseDown:Bool = false) {
 subject.step(dt:1/60,windowFrameInScreen:window,scripted:ScriptedFrameInput(now:epoch+Double(frame)/60,activeKeys:keys,orderedKeys:Array(keys),mouseScreenPos:CGPoint(x:180,y:180),mouseVelocity:velocity,leftMouseDown:mouseDown,rightMouseDown:false,lastMouseMoveTime:epoch,lastMouseClickTime:0,lastKeyActivityTime:epoch))
}
for n in 0..<1140 {idleTick(idleCat,n)}
precondition(idleCat.customAction==nil,"Idle sequence bypassed the initial idle delay")
var sequence:[CustomCatAction]=[]
var sequenceStarted=false
for n in 1140..<(1140+110*60) {
 idleTick(idleCat,n)
 if let action=idleCat.customAction {
  sequenceStarted=true
  if sequence.last != action {sequence.append(action)}
 } else {
  precondition(!sequenceStarted,"Idle sequence returned to the default desk or inserted a cooldown")
 }
 if sequenceStarted && sequence.count>1 {
  precondition(idleCat.customDisplayedPose != "sit_base","Idle transition displayed the default desk")
 }
}
precondition(sequence.count>=15,"Idle sequence did not complete three rounds")
for (i,action) in sequence.enumerated() {
 precondition(action==CustomCatAction.allCases[i % CustomCatAction.allCases.count],"Idle actions skipped/reordered at \(i)")
}
print("PASS three complete automatic idle rounds: all five poses in order, no default desk or cooldown between poses")

// Active input still takes priority, followed by the existing re-entry delay.
idleCat.triggerKeyDown(.d,at:epoch+130)
precondition(idleCat.customAction==nil && idleCat.floatingKeycaps.last?.label=="D")
for n in 7740..<8340 {idleTick(idleCat,n)}
precondition(idleCat.customAction==nil,"Idle sequence resumed before the interaction cooldown")
for n in 8340..<9000 {idleTick(idleCat,n)}
precondition(idleCat.customAction != nil,"Idle sequence failed to resume after interaction")
idleCat.triggerMouseClick(button:0,isDown:true)
precondition(idleCat.customAction==nil)
for (velocity,keys,mouseDown) in [(CGVector(dx:100,dy:0),Set<PhysicalKey>(),false),(.zero,Set([PhysicalKey.d]),false),(.zero,Set<PhysicalKey>(),true)] {
 let activeCat=CatPhysics()
 activeCat.playCustomAction(.nap)
 for n in 0..<60 {idleTick(activeCat,n,velocity:velocity,keys:keys,mouseDown:mouseDown)}
 precondition(activeCat.customAction==nil,"Active input failed to interrupt automatic idle")
}
let manualCat=CatPhysics()
manualCat.playCustomAction(.wave,duration:0.8,manual:true)
for n in 0..<70 {idleTick(manualCat,n)}
precondition(manualCat.customAction==nil,"Manual previews unexpectedly joined automatic idle rotation")
CatSettings.shared.customAutoActions = false
let disabledCat=CatPhysics()
for n in 0..<1800 {idleTick(disabledCat,n)}
precondition(disabledCat.customAction==nil,"Disabled automatic idle still started a sequence")
print("PASS keyboard/mouse wake, re-entry delay, manual previews and automatic idle toggle")

for id in DeskCatIdleAnimation.poseIDs {
 let start=CACurrentMediaTime()
 for n in 0..<60 {autoreleasepool {_=DeskCatIdleAnimation.image(id,age:CGFloat(n)/60)}}
 let ms=(CACurrentMediaTime()-start)/60*1000
 precondition(ms<16,"Idle rendering exceeds a 60 fps budget: \(id), \(ms) ms")
 print(String(format:"PASS %@ rendering: %.2f ms/frame",id,ms))
}
