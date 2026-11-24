import Foundation
import CoreGraphics

/// Canonical physical key identifier shared across IOHIDManager (raw USB HID)
/// and CGEventTap (virtual key codes), ensuring full-state NKRO tracking in both
/// normal typing (any IME) and games.
enum PhysicalKey: Hashable, CaseIterable {
    // Row 0: Number row
    case escape, k1, k2, k3, k4, k5, k6, k7, k8, k9, k0, minus, equal, backspace
    // Row 1: QWERTY
    case tab, q, w, e, r, t, y, u, i, o, p, leftBracket, rightBracket, backslash
    // Row 2: ASDF
    case capsLock, a, s, d, f, g, h, j, k, l, semicolon, quote, enter
    // Row 3: ZXCV
    case leftShift, z, x, c, v, b, n, m, comma, period, slash, rightShift, arrowUp
    // Row 4: Modifiers & Space
    case leftControl, leftOption, leftCommand, space, rightCommand, rightOption, fn, arrowLeft, arrowDown, arrowRight
    // Extra function / nav keys (mapped cleanly onto top/edge key positions)
    case grave, rightControl, forwardDelete
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

    case home, end, pageUp, pageDown, insert, printScreen, scrollLock, pause, application, power
    case numLock, numDivide, numMultiply, numMinus, numPlus, numEnter, numDecimal, numEqual
    case num0, num1, num2, num3, num4, num5, num6, num7, num8, num9
    case f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown, playPause, nextTrack, previousTrack, eject
    case illuminationUp, illuminationDown, illuminationToggle
    case internationalBackslash, yen, underscore, jisKeypadComma, eisu, kana
    // Unknown keys keep their own identity, so simultaneous extra keys are never collapsed.
    case hidUsage(UInt32), virtualKey(UInt16), consumerUsage(UInt32)

    static let allCases: [PhysicalKey] = [.escape, .k1, .k2, .k3, .k4, .k5, .k6, .k7, .k8, .k9, .k0, .minus, .equal, .backspace, .tab, .q, .w, .e, .r, .t, .y, .u, .i, .o, .p, .leftBracket, .rightBracket, .backslash, .capsLock, .a, .s, .d, .f, .g, .h, .j, .k, .l, .semicolon, .quote, .enter, .leftShift, .z, .x, .c, .v, .b, .n, .m, .comma, .period, .slash, .rightShift, .arrowUp, .leftControl, .leftOption, .leftCommand, .space, .rightCommand, .rightOption, .fn, .arrowLeft, .arrowDown, .arrowRight, .grave, .rightControl, .forwardDelete, .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12, .home, .end, .pageUp, .pageDown, .insert, .printScreen, .scrollLock, .pause, .application, .power, .numLock, .numDivide, .numMultiply, .numMinus, .numPlus, .numEnter, .numDecimal, .numEqual, .num0, .num1, .num2, .num3, .num4, .num5, .num6, .num7, .num8, .num9, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20, .f21, .f22, .f23, .f24, .volumeUp, .volumeDown, .mute, .brightnessUp, .brightnessDown, .playPause, .nextTrack, .previousTrack, .eject, .illuminationUp, .illuminationDown, .illuminationToggle, .internationalBackslash, .yen, .underscore, .jisKeypadComma, .eisu, .kana]

    /// Short, clean keycap badge label matching mechanical keycap aesthetics.
    var badgeLabel: String {
        switch self {
        case .escape: return "ESC"
        case .grave: return "~"
        case .k1: return "1"
        case .k2: return "2"
        case .k3: return "3"
        case .k4: return "4"
        case .k5: return "5"
        case .k6: return "6"
        case .k7: return "7"
        case .k8: return "8"
        case .k9: return "9"
        case .k0: return "0"
        case .minus: return "-"
        case .equal: return "="
        case .backspace: return "⌫"
        case .forwardDelete: return "⌦"
        case .tab: return "⇥"
        case .q: return "Q"
        case .w: return "W"
        case .e: return "E"
        case .r: return "R"
        case .t: return "T"
        case .y: return "Y"
        case .u: return "U"
        case .i: return "I"
        case .o: return "O"
        case .p: return "P"
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .backslash: return "\\"
        case .capsLock: return "⇪"
        case .a: return "A"
        case .s: return "S"
        case .d: return "D"
        case .f: return "F"
        case .g: return "G"
        case .h: return "H"
        case .j: return "J"
        case .k: return "K"
        case .l: return "L"
        case .semicolon: return ";"
        case .quote: return "'"
        case .enter: return "↵"
        case .leftShift, .rightShift: return "⇧"
        case .z: return "Z"
        case .x: return "X"
        case .c: return "C"
        case .v: return "V"
        case .b: return "B"
        case .n: return "N"
        case .m: return "M"
        case .comma: return ","
        case .period: return "."
        case .slash: return "/"
        case .leftControl, .rightControl: return "⌃"
        case .leftOption, .rightOption: return "⌥"
        case .leftCommand, .rightCommand: return "⌘"
        case .space: return "␣"
        case .fn: return "Fn"
        case .arrowUp: return "↑"
        case .arrowDown: return "↓"
        case .arrowLeft: return "←"
        case .arrowRight: return "→"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "PgUp"
        case .pageDown: return "PgDn"
        case .insert: return "Ins"
        case .printScreen: return "PrtSc"
        case .scrollLock: return "ScrLk"
        case .pause: return "Pause"
        case .application: return "Menu"
        case .power: return "Power"
        case .numLock: return "NumLk"
        case .numDivide: return "Num /"
        case .numMultiply: return "Num *"
        case .numMinus: return "Num −"
        case .numPlus: return "Num +"
        case .numEnter: return "Num ↵"
        case .numDecimal: return "Num ."
        case .numEqual: return "Num ="
        case .volumeUp: return "音量＋"
        case .volumeDown: return "音量−"
        case .mute: return "静音"
        case .brightnessUp: return "亮度＋"
        case .brightnessDown: return "亮度−"
        case .playPause: return "播放"
        case .nextTrack: return "下一首"
        case .previousTrack: return "上一首"
        case .eject: return "退出盘"
        case .illuminationUp: return "键灯＋"
        case .illuminationDown: return "键灯−"
        case .illuminationToggle: return "键灯"
        case .internationalBackslash: return "ISO \\"
        case .yen: return "¥"
        case .underscore: return "_"
        case .jisKeypadComma: return "Num ,"
        case .eisu: return "英数"
        case .kana: return "かな"
        case .num0: return "Num 0"
        case .num1: return "Num 1"
        case .num2: return "Num 2"
        case .num3: return "Num 3"
        case .num4: return "Num 4"
        case .num5: return "Num 5"
        case .num6: return "Num 6"
        case .num7: return "Num 7"
        case .num8: return "Num 8"
        case .num9: return "Num 9"
        case .f13: return "F13"
        case .f14: return "F14"
        case .f15: return "F15"
        case .f16: return "F16"
        case .f17: return "F17"
        case .f18: return "F18"
        case .f19: return "F19"
        case .f20: return "F20"
        case .f21: return "F21"
        case .f22: return "F22"
        case .f23: return "F23"
        case .f24: return "F24"
        case .hidUsage(let u): return String(format:"HID %02X",u)
        case .virtualKey(let c): return "Key \(c)"
        case .consumerUsage(let u): return String(format:"Media %02X",u)
        }
    }

    /// Which visual keycap on our 65% mini keyboard lights up when this key is pressed.
    var visualKey: PhysicalKey {
        switch self {
        case .grave: return .escape
        case .home, .pageUp: return .arrowUp
        case .end, .pageDown: return .arrowDown
        case .insert, .application: return .fn
        case .numEnter: return .enter
        case .numDecimal, .jisKeypadComma: return .period
        case .numPlus, .numEqual: return .equal
        case .numMinus: return .minus
        case .numMultiply: return .k8
        case .numDivide: return .slash
        case .numLock: return .fn
        case .num0: return .k0
        case .num1: return .k1
        case .num2: return .k2
        case .num3: return .k3
        case .num4: return .k4
        case .num5: return .k5
        case .num6: return .k6
        case .num7: return .k7
        case .num8: return .k8
        case .num9: return .k9
        case .f13: return .f1.visualKey
        case .f14: return .f2.visualKey
        case .f15: return .f3.visualKey
        case .f16: return .f4.visualKey
        case .f17: return .f5.visualKey
        case .f18: return .f6.visualKey
        case .f19: return .f7.visualKey
        case .f20: return .f8.visualKey
        case .f21: return .f9.visualKey
        case .f22: return .f10.visualKey
        case .f23: return .f11.visualKey
        case .f24: return .f12.visualKey

        case .forwardDelete: return .backspace
        case .rightControl: return .fn
        case .f1: return .k1
        case .f2: return .k2
        case .f3: return .k3
        case .f4: return .k4
        case .f5: return .k5
        case .f6: return .k6
        case .f7: return .k7
        case .f8: return .k8
        case .f9: return .k9
        case .f10: return .k0
        case .f11: return .minus
        case .f12: return .equal
        default: return self
        }
    }

    /// Preferred paw in viewer coordinates:
    /// Because the keyboard faces the cat (rotated 180° relative to the viewer),
    /// viewer-left paw = cat's RIGHT hand (mouse + Y-P, H-Enter, N-/, 6-Backspace, Arrows),
    /// viewer-right paw = cat's LEFT hand (WASD, Q-T, A-G, Z-B, Esc, 1-5, Tab, Caps, LShift).
    var prefersLeftPaw: Bool {
        switch self.visualKey {
        case .escape, .k1, .k2, .k3, .k4, .k5, .k6,
             .tab, .q, .w, .e, .r, .t,
             .capsLock, .a, .s, .d, .f, .g,
             .leftShift, .z, .x, .c, .v, .b,
             .leftControl, .leftOption, .leftCommand,
             .space:
            return false // viewer-right paw (cat's left hand — zero arm crossing in WASD + Mouse gaming!)
        default:
            return true  // viewer-left paw (cat's right hand — right half of keyboard + mouse!)
        }
    }

    /// Map USB HID Keyboard/Keypad Usage ID (Page 0x07) -> PhysicalKey
    static func fromHIDUsage(_ usage: UInt32) -> PhysicalKey? {
        // 0xFFFFFFFF is an array-index sentinel, never a keyboard usage.
        // Some devices keep the array flag on valid derived key elements, so
        // validate the usage range rather than rejecting every array element.
        guard usage>=0x04 && usage<=0xE7 else { return nil }
        switch usage {
        case 0x04: return .a
        case 0x05: return .b
        case 0x06: return .c
        case 0x07: return .d
        case 0x08: return .e
        case 0x09: return .f
        case 0x0A: return .g
        case 0x0B: return .h
        case 0x0C: return .i
        case 0x0D: return .j
        case 0x0E: return .k
        case 0x0F: return .l
        case 0x10: return .m
        case 0x11: return .n
        case 0x12: return .o
        case 0x13: return .p
        case 0x14: return .q
        case 0x15: return .r
        case 0x16: return .s
        case 0x17: return .t
        case 0x18: return .u
        case 0x19: return .v
        case 0x1A: return .w
        case 0x1B: return .x
        case 0x1C: return .y
        case 0x1D: return .z
        case 0x1E: return .k1
        case 0x1F: return .k2
        case 0x20: return .k3
        case 0x21: return .k4
        case 0x22: return .k5
        case 0x23: return .k6
        case 0x24: return .k7
        case 0x25: return .k8
        case 0x26: return .k9
        case 0x27: return .k0
        case 0x28: return .enter
        case 0x29: return .escape
        case 0x2A: return .backspace
        case 0x2B: return .tab
        case 0x2C: return .space
        case 0x2D: return .minus
        case 0x2E: return .equal
        case 0x2F: return .leftBracket
        case 0x30: return .rightBracket
        case 0x31: return .backslash
        case 0x33: return .semicolon
        case 0x34: return .quote
        case 0x35: return .grave
        case 0x36: return .comma
        case 0x37: return .period
        case 0x38: return .slash
        case 0x39: return .capsLock
        case 0x3A: return .f1
        case 0x3B: return .f2
        case 0x3C: return .f3
        case 0x3D: return .f4
        case 0x3E: return .f5
        case 0x3F: return .f6
        case 0x40: return .f7
        case 0x41: return .f8
        case 0x42: return .f9
        case 0x43: return .f10
        case 0x44: return .f11
        case 0x45: return .f12
        case 0x4C: return .forwardDelete
        case 0x4F: return .arrowRight
        case 0x50: return .arrowLeft
        case 0x51: return .arrowDown
        case 0x52: return .arrowUp
        // Numpad support (great for gaming & data entry)
        case 0x58: return .numEnter
        case 0x59: return .num1
        case 0x5A: return .num2
        case 0x5B: return .num3
        case 0x5C: return .num4
        case 0x5D: return .num5
        case 0x5E: return .num6
        case 0x5F: return .num7
        case 0x60: return .num8
        case 0x61: return .num9
        case 0x62: return .num0
        case 0x63: return .numDecimal
        case 0x32: return .internationalBackslash
        case 0x46: return .printScreen
        case 0x47: return .scrollLock
        case 0x48: return .pause
        case 0x49: return .insert
        case 0x4A: return .home
        case 0x4B: return .pageUp
        case 0x4D: return .end
        case 0x4E: return .pageDown
        case 0x53: return .numLock
        case 0x54: return .numDivide
        case 0x55: return .numMultiply
        case 0x56: return .numMinus
        case 0x57: return .numPlus
        case 0x65: return .application
        case 0x66: return .power
        case 0x67: return .numEqual
        case 0x68: return .f13
        case 0x69: return .f14
        case 0x6A: return .f15
        case 0x6B: return .f16
        case 0x6C: return .f17
        case 0x6D: return .f18
        case 0x6E: return .f19
        case 0x6F: return .f20
        case 0x70: return .f21
        case 0x71: return .f22
        case 0x72: return .f23
        case 0x73: return .f24
        case 0x7F: return .mute
        case 0x80: return .volumeUp
        case 0x81: return .volumeDown
        case 0x85: return .jisKeypadComma
        case 0x87: return .underscore
        case 0x89: return .yen
        case 0x90: return .kana
        case 0x91: return .eisu
        // Modifiers
        case 0xE0: return .leftControl
        case 0xE1: return .leftShift
        case 0xE2: return .leftOption
        case 0xE3: return .leftCommand
        case 0xE4: return .rightControl
        case 0xE5: return .rightShift
        case 0xE6: return .rightOption
        case 0xE7: return .rightCommand
        default: return .hidUsage(usage)
        }
    }

    /// Map macOS virtual CGKeyCode -> PhysicalKey
    static func fromCGKeyCode(_ code: UInt16) -> PhysicalKey? {
        switch code {
        case 0: return .a
        case 1: return .s
        case 2: return .d
        case 3: return .f
        case 4: return .h
        case 5: return .g
        case 6: return .z
        case 7: return .x
        case 8: return .c
        case 9: return .v
        case 11: return .b
        case 12: return .q
        case 13: return .w
        case 14: return .e
        case 15: return .r
        case 16: return .y
        case 17: return .t
        case 18: return .k1
        case 19: return .k2
        case 20: return .k3
        case 21: return .k4
        case 22: return .k6
        case 23: return .k5
        case 24: return .equal
        case 25: return .k9
        case 26: return .k7
        case 27: return .minus
        case 28: return .k8
        case 29: return .k0
        case 30: return .rightBracket
        case 31: return .o
        case 32: return .u
        case 33: return .leftBracket
        case 34: return .i
        case 35: return .p
        case 36: return .enter
        case 37: return .l
        case 38: return .j
        case 39: return .quote
        case 40: return .k
        case 41: return .semicolon
        case 42: return .backslash
        case 43: return .comma
        case 44: return .slash
        case 45: return .n
        case 46: return .m
        case 47: return .period
        case 48: return .tab
        case 49: return .space
        case 50: return .grave
        case 51: return .backspace
        case 53: return .escape
        case 54: return .rightCommand
        case 55: return .leftCommand
        case 56: return .leftShift
        case 57: return .capsLock
        case 58: return .leftOption
        case 59: return .leftControl
        case 60: return .rightShift
        case 61: return .rightOption
        case 62: return .rightControl
        case 63: return .fn
        case 76: return .numEnter
        case 82: return .num0
        case 83: return .num1
        case 84: return .num2
        case 85: return .num3
        case 86: return .num4
        case 87: return .num5
        case 88: return .num6
        case 89: return .num7
        case 91: return .num8
        case 92: return .num9
        case 96: return .f5
        case 97: return .f6
        case 98: return .f7
        case 99: return .f3
        case 100: return .f8
        case 101: return .f9
        case 103: return .f11
        case 109: return .f10
        case 111: return .f12
        case 117: return .forwardDelete
        case 118: return .f4
        case 120: return .f2
        case 122: return .f1
        case 10: return .internationalBackslash
        case 64: return .f17
        case 65: return .numDecimal
        case 67: return .numMultiply
        case 69: return .numPlus
        case 71: return .numLock
        case 72: return .volumeUp
        case 73: return .volumeDown
        case 74: return .mute
        case 75: return .numDivide
        case 78: return .numMinus
        case 79: return .f18
        case 80: return .f19
        case 81: return .numEqual
        case 90: return .f20
        case 93: return .yen
        case 94: return .underscore
        case 95: return .jisKeypadComma
        case 102: return .eisu
        case 104: return .kana
        case 105: return .f13
        case 106: return .f16
        case 107: return .f14
        case 113: return .f15
        case 114: return .insert
        case 115: return .home
        case 116: return .pageUp
        case 119: return .end
        case 121: return .pageDown
        case 123: return .arrowLeft
        case 124: return .arrowRight
        case 125: return .arrowDown
        case 126: return .arrowUp
        default: return .virtualKey(code)
        }
    }
    static func fromConsumerUsage(_ usage: UInt32) -> PhysicalKey {
        switch usage {
        case 0xE9: return .volumeUp
        case 0xEA: return .volumeDown
        case 0xE2: return .mute
        case 0x6F: return .brightnessUp
        case 0x70: return .brightnessDown
        case 0xCD: return .playPause
        case 0xB5: return .nextTrack
        case 0xB6: return .previousTrack
        case 0xB8: return .eject
        default: return .consumerUsage(usage)
        }
    }
    static func fromSystemKey(_ code: Int) -> PhysicalKey? {
        let keys: [Int:PhysicalKey] = [0:.volumeUp,1:.volumeDown,2:.brightnessUp,3:.brightnessDown,7:.mute,10:.numLock,14:.eject,16:.playPause,17:.nextTrack,18:.previousTrack,19:.nextTrack,20:.previousTrack,21:.illuminationUp,22:.illuminationDown,23:.illuminationToggle]
        return keys[code]
    }

}

/// Visual definition of a single keycap on the mini 65% mechanical keyboard.
struct VisualKeycap {
    let key: PhysicalKey
    let row: Int
    let xUnits: CGFloat      // start X in normalized [0..1] keyboard interior units
    let widthUnits: CGFloat  // width in normalized [0..1] units
    let isAmberAccent: Bool
    /// Normalized center (u in 0..1, v in 0..1) inside the keyboard key-well
    var normalizedCenter: CGPoint {
        let u = xUnits + widthUnits * 0.5
        let v = (CGFloat(row) + 0.5) / 5.0
        return CGPoint(x: u, y: v)
    }
}

/// Complete 65% mini mechanical keyboard layout facing the cat (180° rotated relative to viewer),
/// matching the reference video's Spacebar closest to the cat, amber Enter on left, and amber Esc at bottom-right!
enum KeyboardLayout {
    static let keycaps: [VisualKeycap] = {
        let rows: [[(PhysicalKey, CGFloat, Bool)]] = [
            // Row 0: 15.0u total (Esc is amber -> lands at bottom-right corner when facing cat!)
            [
                (.escape, 1.0, true), (.k1, 1.0, false), (.k2, 1.0, false), (.k3, 1.0, false),
                (.k4, 1.0, false), (.k5, 1.0, false), (.k6, 1.0, false), (.k7, 1.0, false),
                (.k8, 1.0, false), (.k9, 1.0, false), (.k0, 1.0, false), (.minus, 1.0, false),
                (.equal, 1.0, false), (.backspace, 2.0, false)
            ],
            // Row 1: 15.0u total
            [
                (.tab, 1.5, false), (.q, 1.0, false), (.w, 1.0, false), (.e, 1.0, false),
                (.r, 1.0, false), (.t, 1.0, false), (.y, 1.0, false), (.u, 1.0, false),
                (.i, 1.0, false), (.o, 1.0, false), (.p, 1.0, false), (.leftBracket, 1.0, false),
                (.rightBracket, 1.0, false), (.backslash, 1.5, false)
            ],
            // Row 2: 15.0u total (Enter is amber -> lands on middle-left edge when facing cat!)
            [
                (.capsLock, 1.75, false), (.a, 1.0, false), (.s, 1.0, false), (.d, 1.0, false),
                (.f, 1.0, false), (.g, 1.0, false), (.h, 1.0, false), (.j, 1.0, false),
                (.k, 1.0, false), (.l, 1.0, false), (.semicolon, 1.0, false), (.quote, 1.0, false),
                (.enter, 2.25, true)
            ],
            // Row 3: 15.0u total
            [
                (.leftShift, 2.25, false), (.z, 1.0, false), (.x, 1.0, false), (.c, 1.0, false),
                (.v, 1.0, false), (.b, 1.0, false), (.n, 1.0, false), (.m, 1.0, false),
                (.comma, 1.0, false), (.period, 1.0, false), (.slash, 1.0, false),
                (.rightShift, 1.75, false), (.arrowUp, 1.0, false)
            ],
            // Row 4: 15.0u total (Spacebar row -> lands on TOP row closest to the cat!)
            [
                (.leftControl, 1.25, false), (.leftOption, 1.25, false), (.leftCommand, 1.25, false),
                (.space, 6.25, false),
                (.rightCommand, 1.0, false), (.rightOption, 1.0, false),
                (.arrowLeft, 1.0, false), (.arrowDown, 1.0, false), (.arrowRight, 1.0, false)
            ]
        ]

        var result: [VisualKeycap] = []
        let totalUnits: CGFloat = 15.0
        for (rowIdx, row) in rows.enumerated() {
            var cursor: CGFloat = 0
            for (key, width, isAmber) in row {
                result.append(VisualKeycap(
                    key: key,
                    row: rowIdx,
                    xUnits: cursor / totalUnits,
                    widthUnits: width / totalUnits,
                    isAmberAccent: isAmber
                ))
                cursor += width
            }
        }
        return result
    }()

    static let lookup: [PhysicalKey: VisualKeycap] = {
        var dict: [PhysicalKey: VisualKeycap] = [:]
        for cap in keycaps {
            dict[cap.key] = cap
        }
        return dict
    }()

    /// Screen-space keyboard quad point (su in 0..1 left-to-right, sv in 0..1 top-to-bottom).
    static func screenQuadPoint(su: CGFloat, sv: CGFloat) -> CGPoint {
        let topLeft = CGPoint(x: 109, y: 238)
        let topRight = CGPoint(x: 281, y: 247)
        let bottomLeft = CGPoint(x: 103, y: 282)
        let bottomRight = CGPoint(x: 286, y: 292)

        let topX = topLeft.x + (topRight.x - topLeft.x) * su
        let topY = topLeft.y + (topRight.y - topLeft.y) * su
        let botX = bottomLeft.x + (bottomRight.x - bottomLeft.x) * su
        let botY = bottomLeft.y + (bottomRight.y - bottomLeft.y) * su

        return CGPoint(
            x: topX + (botX - topX) * sv,
            y: topY + (botY - topY) * sv
        )
    }

    /// Convert logical keyboard (u, v) into 360x320 canvas coordinates,
    /// rotated 180° so the keyboard faces the cat (Spacebar at top closest to cat, Esc at bottom-right!).
    static func canvasPoint(u: CGFloat, v: CGFloat) -> CGPoint {
        screenQuadPoint(su: 1.0 - u, sv: 1.0 - v)
    }

    static func canvasPoint(for key: PhysicalKey) -> CGPoint {
        let vk = key.visualKey
        if let cap = lookup[vk] {
            let c = cap.normalizedCenter
            return canvasPoint(u: c.x, v: c.y)
        }
        return canvasPoint(u: 0.5, v: 0.5)
    }
}
