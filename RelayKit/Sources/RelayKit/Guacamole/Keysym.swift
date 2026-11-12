import Foundation

/// Keysyms X11 utilisés par Guacamole (instruction `key`).
public enum Keysym {
    public static let backspace = 0xFF08
    public static let tab = 0xFF09
    public static let enter = 0xFF0D
    public static let escape = 0xFF1B
    public static let home = 0xFF50
    public static let left = 0xFF51
    public static let up = 0xFF52
    public static let right = 0xFF53
    public static let down = 0xFF54
    public static let pageUp = 0xFF55
    public static let pageDown = 0xFF56
    public static let end = 0xFF57
    public static let insert = 0xFF63
    public static let delete = 0xFFFF
    public static let shiftLeft = 0xFFE1
    public static let controlLeft = 0xFFE3
    public static let altLeft = 0xFFE9
    public static let superLeft = 0xFFEB
    public static let altRight = 0xFFEA

    public static func function(_ n: Int) -> Int { 0xFFBE + (max(1, min(n, 12)) - 1) }

    /// Keysym d'un caractère tapé : Latin-1 direct, sinon forme Unicode (0x0100xxxx).
    public static func from(scalar: Unicode.Scalar) -> Int {
        let v = Int(scalar.value)
        switch v {
        case 0x0A, 0x0D: return enter
        case 0x09: return tab
        case 0x08, 0x7F: return backspace
        case 0x1B: return escape
        case 0x20...0xFF: return v
        case 0x100...0x10FFFF: return 0x0100_0000 | v
        default: return 0
        }
    }

    /// Keysyms d'un texte inséré, dans l'ordre (chaque caractère donne un appui + relâchement).
    public static func sequence(for text: String) -> [Int] {
        text.unicodeScalars.map(from(scalar:)).filter { $0 != 0 }
    }
}

/// Masque des boutons de l'instruction `mouse`.
public struct MouseButtons: OptionSet, Sendable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let left = MouseButtons(rawValue: 1)
    public static let middle = MouseButtons(rawValue: 2)
    public static let right = MouseButtons(rawValue: 4)
    public static let scrollUp = MouseButtons(rawValue: 8)
    public static let scrollDown = MouseButtons(rawValue: 16)
}
