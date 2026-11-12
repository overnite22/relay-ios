import Foundation

/// Instruction du protocole Guacamole : `len.opcode,len.arg,…;` (longueurs en caractères Unicode).
public struct GuacInstruction: Equatable, Sendable {
    public var opcode: String
    public var args: [String]

    public init(_ opcode: String, _ args: [String] = []) {
        self.opcode = opcode
        self.args = args
    }

    public init(_ opcode: String, _ args: String...) {
        self.opcode = opcode
        self.args = args
    }

    public func encoded() -> String {
        var out = ""
        for (i, element) in ([opcode] + args).enumerated() {
            if i > 0 { out.append(",") }
            out.append(String(element.unicodeScalars.count))
            out.append(".")
            out.append(element)
        }
        out.append(";")
        return out
    }

    public func int(_ index: Int) -> Int { index < args.count ? Int(args[index]) ?? 0 : 0 }
    public func double(_ index: Int) -> Double { index < args.count ? Double(args[index]) ?? 0 : 0 }
    public func string(_ index: Int) -> String { index < args.count ? args[index] : "" }
}

public enum GuacParseError: Error, Equatable {
    case malformed(String)
}

/// Analyseur incrémental : accepte des fragments et renvoie les instructions complètes.
public struct GuacParser: Sendable {
    private var pending = ""

    public init() {}

    public mutating func feed(_ text: String) throws -> [GuacInstruction] {
        pending += text
        var out: [GuacInstruction] = []
        let scalars = pending.unicodeScalars
        var cursor = scalars.startIndex
        var elements: [String] = []
        var instructionStart = cursor
        while cursor < scalars.endIndex {
            // Longueur.
            var length = 0
            var digits = 0
            while cursor < scalars.endIndex, let d = Self.digit(scalars[cursor]) {
                length = length * 10 + d
                digits += 1
                cursor = scalars.index(after: cursor)
                if digits > 9 { throw GuacParseError.malformed("longueur trop grande") }
            }
            guard cursor < scalars.endIndex else { break }
            guard digits > 0, scalars[cursor] == "." else { throw GuacParseError.malformed("séparateur de longueur attendu") }
            cursor = scalars.index(after: cursor)
            // Valeur.
            guard let valueEnd = scalars.index(cursor, offsetBy: length, limitedBy: scalars.endIndex) else { break }
            let value = String(scalars[cursor..<valueEnd])
            cursor = valueEnd
            guard cursor < scalars.endIndex else { break }
            let terminator = scalars[cursor]
            cursor = scalars.index(after: cursor)
            elements.append(value)
            if terminator == "," {
                continue
            } else if terminator == ";" {
                out.append(GuacInstruction(elements[0], Array(elements.dropFirst())))
                elements.removeAll(keepingCapacity: true)
                instructionStart = cursor
            } else {
                throw GuacParseError.malformed("terminaison inattendue")
            }
        }
        pending = String(scalars[instructionStart...])
        if pending.unicodeScalars.count > 16 << 20 { throw GuacParseError.malformed("instruction trop longue") }
        return out
    }

    private static func digit(_ s: Unicode.Scalar) -> Int? {
        s.value >= 48 && s.value <= 57 ? Int(s.value - 48) : nil
    }
}
